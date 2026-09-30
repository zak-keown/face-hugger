# Theme — compact actual token summary

## Implemented values

- Framework appearance: native SwiftUI/AppKit, system light/dark appearance. No CSS :root/.dark variables, theme provider, or external fonts.
- App accent/tint: `Color(red: 0.68, green: 0.45, blue: 0.03)` ≈ `#AD7308`.
- Upload folder icon: `Color(red: 0.33, green: 0.64, blue: 0.83)` ≈ `#54A3D4`.
- Semantic colors: primary/secondary/tertiary text, `.background.secondary` inspector, `.quaternary` error background; system `.orange` running/warning, `.green` completed, `.red` failed, `.yellow` progress and drop target, `.blue` remote folders. Actual RGB varies with system appearance for semantic colors.
- Typography: system font (SF on macOS); `.title2.weight(.semibold)` prominent titles, `.title3.weight(.semibold)` queue header, `.headline` row titles, `.callout` metadata/forms, `.caption` help and status, `.caption2` locks. Logs use `.system(.caption, design: .monospaced)`; counters `.monospacedDigit()`. SF Symbols use title/title2 or explicit 30-point folder icon. No custom global type scale.
- Spacing: local values 2, 3, 4, 5, 6, 7, 8, 10, 11, 12, 13, 14, 16, 18, 20, 22, 24 points. Main header padding 20; repo header and inspector padding 22; sheet padding 24.
- Corners: error banner 8; drop-target outline 12 with line width 4. Most controls use native corners. No custom shadows or decorative gradients.
- Window default 1180×740; minimum 880×560. Sidebar min/ideal/max 200/225/280; main content minimum 390; inspector min/ideal/max 265/300/360. Native split-view resizing; no web breakpoints.
- Sheets: upload 600×710, settings 560×650, create-repo 470×360. File filter input width 180; file size table column width 100.
- Mascot: `Image("Hugger")`, empty state 160×160 and upload sheet 56×56. Asset `Resources/Assets.xcassets/Hugger.imageset/hugger.png`; master `Resources/Artwork/face-hugger-master.png`. Preserve approved art: smiling HF-style yellow emoji wrapped by tan Alien-style segmented fingers/tail, non-scary. Do not replace with a generic cute bug/folder.

## Existing art-direction target (not all implemented tokens)

`.superdesign/design-system.md` is design intent, not a live theme definition. Its proposed #FFD24B yellow, #B76B00 amber, #3699E3 folder blue, #29313B ink, 24-point title, 1200×780 canvas, toolbar inspector toggle, and pinned/grouped repo notions must not be mistaken for values/features implemented by source. Preserve native macOS structure and approved mascot while distinguishing changes from current behavior.

# Raw theme-bearing sources

There are no dedicated token/config/CSS files. The complete app-level tint definition follows; all local modifiers appear in the full MainView/RepoBrowser sources in layouts.md and component sources in components.md. Sheet source below provides the remaining local styling. The existing design-intent file is included verbatim and explicitly remains intent.

### `Sources/FaceHugger/FaceHuggerApp.swift`

```swift
import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.installing == true {
            let alert = NSAlert(); alert.messageText = "Upload tools are still being installed"
            alert.informativeText = "Please let setup finish before quitting Face Hugger."
            alert.addButton(withTitle: "Continue setup"); alert.runModal()
            return .terminateCancel
        }
        guard let model, model.activeJob != nil else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "Stop uploading and quit?"
        alert.informativeText = "You can resume this upload next time you open Face Hugger. Files already committed will remain on Hugging Face. Closing the window instead keeps your upload running."
        alert.addButton(withTitle: "Keep uploading"); alert.addButton(withTitle: "Stop and quit")
        if alert.runModal() == .alertSecondButtonReturn {
            model.stop()
            Task { @MainActor in
                while model.activeJob != nil { try? await Task.sleep(for: .milliseconds(100)) }
                NSApp.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateCancel
    }
}

@main
struct FaceHuggerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    var body: some Scene {
        Window("Face Hugger", id: "main") {
            MainView(model: model)
                .tint(Color(red: 0.68, green: 0.45, blue: 0.03))
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Upload…") { model.chooseFolder() }.keyboardShortcut("n")
                Button("New Repository…") { model.showCreateRepo = true }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.showSettings = true }.keyboardShortcut(",")
            }
        }
        MenuBarExtra("Face Hugger", systemImage: model.activeJob == nil ? "tray.and.arrow.up" : "arrow.up.circle.fill") {
            MenuContent(model: model)
        }
    }
}

struct MenuContent: View {
    @Bindable var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let job = model.activeJob {
            Text("Uploading \(job.title)")
            Text(job.repo.name)
            Button("Stop Uploads") { model.stop() }
        } else { Text("No active uploads") }
        Divider()
        Button("Show Face Hugger") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit Face Hugger") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
```

### `Sources/FaceHugger/Sheets.swift`

```swift
import AppKit
import SwiftUI

struct UploadSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var repoName = ""
    @State private var kind: RepoKind = .model
    @State private var destination = ""
    @State private var includes = ""
    @State private var excludes = ".DS_Store\n**/.DS_Store"
    @State private var validation: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image("Hugger").resizable().scaledToFit().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) { Text("New upload").font(.title2.weight(.semibold)); Text("Give your files a home on Hugging Face.").foregroundStyle(.secondary) }
            }
            Form {
                Section("Local folder") {
                    HStack { Text(model.draftSource.isEmpty ? "Choose a folder" : model.draftSource).lineLimit(2).textSelection(.enabled); Spacer(); Button("Choose…") { model.chooseFolder() } }
                }
                Section("Destination") {
                    TextField("Repository", text: $repoName, prompt: Text("username/my-model"))
                    if !model.repos.isEmpty {
                        Picker("Recent repositories", selection: $repoName) {
                            Text("Choose a repository").tag("")
                            ForEach(model.repos) { Text($0.name + " (\($0.kind.rawValue))").tag($0.name) }
                        }.onChange(of: repoName) { _, name in if let repo = model.repos.first(where: { $0.name == name }) { kind = repo.kind } }
                    }
                    Picker("Type", selection: $kind) { Text("Model").tag(RepoKind.model); Text("Dataset").tag(RepoKind.dataset) }
                    TextField("Folder in repo", text: $destination, prompt: Text("Root of repository"))
                }
                Section("File filters") {
                    TextField("Include patterns", text: $includes, prompt: Text("All files"), axis: .vertical).lineLimit(1...3)
                    TextField("Exclude patterns", text: $excludes, axis: .vertical).lineLimit(2...4)
                    Text(verbatim: "One glob pattern per line. Example: *.safetensors or **/logs/**. Hugging Face also applies its ignore rules.").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    Label("Matching remote paths may be replaced.", systemImage: "info.circle")
                    Text("Other remote files stay in place. Large uploads may become visible in several commits. The repository must already exist; create one from the sidebar to choose its visibility.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            if let validation { Text(validation).foregroundStyle(.red).font(.callout) }
            ErrorBanner(model: model)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add to queue") { submit(start: false) }
                Button("Upload now") { submit(start: true) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 600, height: 710)
        .onAppear { if let repo = model.currentRepo { repoName = repo.name; kind = repo.kind; destination = model.remotePath } }
    }
    private func patterns(_ text: String) -> [String] { text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private func submit(start: Bool) {
        let name = repoName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = UploadValidation.error(source: model.draftSource, repo: name, destination: path) { validation = problem; return }
        guard model.runtimeReady else { validation = "Set up upload tools in Settings first."; return }
        let selectedRepo = model.currentRepo.flatMap { $0.name == name && $0.kind == kind ? $0 : nil }
        let repo = model.repos.first { $0.name == name && $0.kind == kind } ?? selectedRepo ?? HubRepo(name: name, kind: kind)
        model.addJob(UploadJob(source: model.draftSource, repo: repo, destination: path, includes: patterns(includes), excludes: patterns(excludes)), start: start)
        dismiss()
    }
}

struct SettingsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Make yourself at home.").font(.title2.weight(.semibold))
            Form {
                Section("Upload tools") {
                    Label(model.runtimeReady ? "Hugging Face tools are ready" : "Set up Hugging Face tools", systemImage: model.runtimeReady ? "checkmark.circle.fill" : "shippingbox")
                    Text("Face Hugger uses an isolated Python environment for the official Hugging Face CLI. Setup requires uv and an internet connection.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button(model.runtimeReady ? "Repair upload tools" : "Set up upload tools") { Task { await model.installRuntime() } }.disabled(model.installing || model.activeJob != nil); if model.installing { ProgressView().controlSize(.small) }; Link("Get uv", destination: URL(string: "https://docs.astral.sh/uv/getting-started/installation/")!) }
                    if !model.setupLog.isEmpty {
                        ScrollView { Text(model.setupLog).font(.system(.caption, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(height: 90)
                    }
                }
                Section("Hugging Face account") {
                    if let identity = model.identity {
                        LabeledContent("Connected as", value: identity.name)
                        Button("Remove saved account") { model.disconnect() }.disabled(model.activeJob != nil)
                    }
                    SecureField("Access token", text: $token, prompt: Text("hf_…"))
                    Text("Use a token with write access to your target repositories. It’s stored in your Mac’s Keychain. Leave this blank to use an existing Hugging Face CLI login.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Link("Create a token", destination: URL(string: "https://huggingface.co/settings/tokens")!)
                        Spacer()
                        if model.accountBusy { ProgressView().controlSize(.small) }
                        Button("Connect") { Task { await model.connect(token: token.isEmpty ? nil : token); if model.identity != nil { token = "" } } }.disabled(!model.runtimeReady || model.accountBusy || model.activeJob != nil)
                    }
                }
                Section("While uploading") {
                    Toggle("Keep Mac awake during uploads", isOn: $model.keepAwake).disabled(model.activeJob != nil)
                    Text("Closing the window keeps uploads running in the menu bar. Quitting stops the active upload; you can resume next time.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            ErrorBanner(model: model)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 560, height: 650)
    }
}

struct CreateRepoSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var owner = ""
    @State private var name = ""
    @State private var kind: RepoKind = .model
    @State private var isPrivate = true
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("New repository").font(.title2.weight(.semibold))
            Form {
                TextField("Owner", text: $owner)
                TextField("Name", text: $name, prompt: Text("my-model"))
                Picker("Type", selection: $kind) { Text("Model").tag(RepoKind.model); Text("Dataset").tag(RepoKind.dataset) }
                Toggle("Private repository", isOn: $isPrivate)
                if !isPrivate { Text("Anyone will be able to see files uploaded to this repository.").font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
            ErrorBanner(model: model)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction); Spacer()
                if model.loading { ProgressView().controlSize(.small) }
                Button("Create repository") { Task { await model.createRepo(name: "\(owner)/\(name)", kind: kind, isPrivate: isPrivate) } }
                    .buttonStyle(.borderedProminent).disabled(owner.isEmpty || name.isEmpty || model.loading || !model.runtimeReady).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 470, height: 360).onAppear { owner = model.identity?.name ?? "" }
    }
}

struct ErrorBanner: View {
    @Bindable var model: AppModel
    var body: some View {
        if let error = model.error {
            HStack(alignment: .top) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                Text(error).font(.callout).textSelection(.enabled).lineLimit(4)
                Spacer()
                Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss error")
            }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
```

### `.superdesign/design-system.md` (design intent)

```markdown
# Face Hugger

Native macOS SwiftUI utility for moving folders to Hugging Face, now undergoing a deliberate product redesign. The prior generic sidebar/queue/inspector composition was rejected by the user. Source code is functional context, not a visual template to preserve.

## Identity

Preserve the approved glossy smiling yellow emoji wrapped by a tan Alien-style facehugger. Exact Brand Asset: Resources-Assets.xcassets-Hugger.imageset-hugger.png. Use the supplied image, never substitute an emoji, new mark, or invented drawing. Give it an intentional small home at the junction of local and remote work; do not center it above a slogan in a blank screen.

## Direction under exploration

The product should visibly connect a folder on this Mac to a repository on Hugging Face. Native direct manipulation, a readable file surface, a searchable destination selector, and persistent upload activity replace a long upload form. Saved source/destination pairings are a proposed improvement for repeat work, not existing functionality. No automatic sync or deletion implied.

Palette: source porcelain #F5F3EE, remote cloud #F8FAFC, ink/slate #253443, butter gold #F6C845, transfer blue #3689BE, secondary text #64707C. Primary action uses dark text on gold. Restrained success green and error red always have text. A deep slate activity shelf can anchor the window; no neon, gradients, decorative charts, dashboard card grids, or fake terminal styling.

SF Pro system typography: 24–28 pt folder/repo names, 15–16 pt section titles, 13–14 pt readable file rows and controls, 12 pt metadata floor. SF Mono only for raw logs, not headings or labels. Align file columns carefully. 8/12/16/24/32 spacing; avoid excess padding that forces scrolling in ordinary windows. Native window controls, menus, focus, resizable panes and keyboard behavior remain.

One memorable structural move per concept. Full contiguous work surfaces, hierarchy through material and placement rather than a border around everything. Warm character and serious file handling should coexist. Empty states show where to put a folder and choose a destination within the same useful workspace.

## Truthful behavior

Preparation, upload/reuse and commits overlap; never imply a sequential three-step wizard or invented overall percentage, speed or ETA. Show reported stage counts. Stop and Resume are accurate; do not promise pause. Local staging previews, saved pairings, and matching-path summaries are proposals requiring implementation. Show only feasible metadata in concepts and identify mock data as illustrative in presentation. Remote visibility must remain obvious before upload. Remote replacement affects matching paths, not unrelated files. Logs are an optional drawer. Mac may keep working after its window closes.

Design application windows at 1240×820, not landing pages. Realistic modest fixtures: rena-checkpoint, tokenizer.json, config.json, model-00001-of-00004.safetensors, owner/rena-7b. Avoid multi-terabyte examples.
```
