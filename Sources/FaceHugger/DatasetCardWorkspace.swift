import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A snapshot of the selected folder and filters, with its own security-scope lease.
@MainActor @Observable
final class DatasetCardWorkspace: Identifiable {
    let id = UUID()
    let access: FolderAccess
    let includes: [String]
    let excludes: [String]
    let destination: String
    let repository: String?
    var input: DatasetCardInput
    private var composedInput: DatasetCardInput
    private var savedInput: DatasetCardInput
    var facts: DatasetCardFacts?
    var markdown = ""
    var original = ""
    var savedText = ""
    var hasExistingCard = false
    var busy = false
    var generating = false
    var error: String?
    var notice: String?
    var availabilityReason = DatasetCardGenerator.availabilityReason
    private var operation: Task<Void, Never>?

    init(access: FolderAccess, includes: [String], excludes: [String], destination: String, repository: String?) {
        self.access = access; self.includes = includes; self.excludes = excludes
        self.destination = destination; self.repository = repository
        let initial = DatasetCardInput(title: access.url.lastPathComponent)
        input = initial; composedInput = initial; savedInput = initial
    }
    var isDirty: Bool { markdown != savedText || input != savedInput }
    var notesNeedApplying: Bool { input != composedInput }

    func load() {
        guard facts == nil, !busy else { return }
        busy = true
        let source = access.url, includes = includes, excludes = excludes, destination = destination
        operation = Task {
            defer { busy = false }
            let work = Task.detached {
                try DatasetCardFacts.collect(source: source, includes: includes, excludes: excludes, uploadPath: destination)
            }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await work.value }, onCancel: { work.cancel() })
                try Task.checkCancellation()
                facts = result
                // Existing content is shown to the person, never sent to the model.
                let readme = source.appendingPathComponent("README.md")
                if FileManager.default.fileExists(atPath: readme.path) {
                    do {
                        original = try Self.readCard(readme)
                        hasExistingCard = true
                        markdown = original
                        savedText = original
                        notice = "Existing local README loaded. Drafting creates a replacement to review in Changes."
                    } catch {
                        self.error = "The existing README could not be opened: \(error.localizedDescription) Save a new draft under another name."
                        markdown = DatasetCard.render(facts: result, input: input)
                    }
                } else {
                    markdown = DatasetCard.render(facts: result, input: input)
                }
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    func compose(useModel: Bool) {
        guard let facts, !busy else { return }
        error = nil; notice = nil; busy = true; generating = useModel
        let input = input
        operation = Task {
            defer { busy = false; generating = false; availabilityReason = DatasetCardGenerator.availabilityReason }
            do {
                let draft = useModel ? try await DatasetCardGenerator.draft(facts: facts, input: input) : DatasetCard.render(facts: facts, input: input)
                try Task.checkCancellation()
                markdown = draft
                composedInput = input
                notice = useModel ? "Drafted on this Mac. Check every claim and complete the TODOs before sharing." : "Template updated from your notes and measured facts. Complete the TODOs before sharing."
            } catch is CancellationError { notice = "Drafting cancelled. Your text is unchanged." }
            catch { self.error = "Couldn’t draft on this Mac. Your text is unchanged. You can still use the template. \(error.localizedDescription)" }
        }
    }

    func cancel() { operation?.cancel() }

    func save(onSaved: () -> Void) {
        let panel = NSSavePanel()
        panel.title = "Save dataset card"
        panel.nameFieldStringValue = "README.md"
        panel.directoryURL = access.url
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.message = "Saves a local file. To publish it, include README.md in a new upload to the repository root."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            savedText = markdown
            savedInput = composedInput
            notice = "Saved \(url.lastPathComponent). Nothing has been uploaded. Create a new upload when you’re ready."
            onSaved()
        } catch { self.error = "Couldn’t save the card: \(error.localizedDescription)" }
    }

    private static func readCard(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 256 * 1024 + 1) ?? Data()
        guard data.count <= 256 * 1024, let text = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return text
    }
}
