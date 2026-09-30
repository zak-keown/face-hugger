import AppKit
import SwiftUI

/// Remote half of Transfer Bench; the parent owns repository selection.
struct RepoBrowser: View {
    @Bindable var model: AppModel
    let repo: HubRepo
    var chooseRepository: (() -> Void)? = nil
    @State private var selection: String?
    @State private var search = ""
    @State private var pendingDelete: RemoteEntry?

    var body: some View {
        VStack(spacing: 0) {
            header
            rule
            filterBar
            rule
            fileSurface
            rule
            footer
        }
        .background(BenchTheme.remote)
        .foregroundStyle(BenchTheme.ink)
        .onChange(of: repo.id) { _, _ in selection = nil; search = "" }
        .onChange(of: model.remotePath) { _, _ in selection = nil }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "file")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            if let entry = pendingDelete {
                Button("Delete file", role: .destructive) { Task { await model.delete(entry, from: repo) }; pendingDelete = nil }
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("This creates a deletion commit on \(repo.name). It does not erase the file from the repository’s history.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("On Hugging Face").font(BenchTheme.metadata.weight(.medium))
                Spacer()
                Label(repo.isPrivate ? "Private" : "Public", systemImage: repo.isPrivate ? "lock" : "globe").font(BenchTheme.metadata)
            }.foregroundStyle(BenchTheme.secondary).frame(height: 14).padding(.bottom, 8)
            HStack(spacing: 8) {
                if let chooseRepository {
                    Button(action: chooseRepository) {
                        HStack(spacing: 8) {
                            Text(shortName).font(BenchTheme.title).lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold)).foregroundStyle(BenchTheme.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help("Choose a repository").accessibilityLabel("Choose repository, \(repo.name)")
                } else { Text(shortName).font(BenchTheme.title).lineLimit(1).truncationMode(.middle) }
                Spacer(minLength: 0)
            }.frame(height: 30, alignment: .leading).padding(.bottom, 4)
            HStack {
                Text(repo.name).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                Spacer(minLength: 8)
                Text(repo.kind == .model ? "Model" : "Dataset")
            }.font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary).frame(height: 16).padding(.bottom, 10)
            HStack(spacing: 9) {
                Button { Task { await model.browse(repo) } } label: { Image(systemName: "folder") }
                    .buttonStyle(.plain).help("Repository root").accessibilityLabel("Repository root")
                Text(model.remotePath.isEmpty ? "Repository root" : "/ " + model.remotePath)
                    .lineLimit(1).truncationMode(.middle).help(model.remotePath.isEmpty ? "Repository root" : model.remotePath)
                Spacer(minLength: 4)
                if !model.remotePath.isEmpty {
                    Button { goUp() } label: { Image(systemName: "arrow.up") }
                        .buttonStyle(.plain).help("Open parent folder").accessibilityLabel("Open parent folder")
                }
                Button { Task { await model.browse(repo, path: model.remotePath) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Refresh files").accessibilityLabel("Refresh files")
                Button { NSWorkspace.shared.open(repo.url) } label: { Image(systemName: "arrow.up.right.square") }
                    .buttonStyle(.plain).help("Open repository on Hugging Face").accessibilityLabel("Open repository on Hugging Face")
            }.font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary).frame(height: 20)
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
        .frame(height: BenchTheme.paneHeaderHeight)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(BenchTheme.secondary)
            TextField("Find in this folder", text: $search).textFieldStyle(.plain).accessibilityLabel("Filter remote files")
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(BenchTheme.secondary) }
                    .buttonStyle(.plain).help("Clear filter").accessibilityLabel("Clear remote file filter")
            }
        }.font(BenchTheme.metadata).padding(.horizontal, 24).frame(height: BenchTheme.utilityHeight)
    }

    @ViewBuilder private var fileSurface: some View {
        if model.loading {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Loading remote files…").font(BenchTheme.body).foregroundStyle(BenchTheme.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredEntries.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                Image(systemName: search.isEmpty ? "folder" : "magnifyingglass").font(.system(size: 25, weight: .light))
                    .foregroundStyle(BenchTheme.secondary).padding(.bottom, 4)
                Text(search.isEmpty ? "Ready for your files" : "No matching files").font(BenchTheme.section)
                Text(search.isEmpty ? "Uploads will arrive in this folder." : "Try another name or clear the filter.")
                    .font(BenchTheme.body).foregroundStyle(BenchTheme.secondary)
                if !search.isEmpty { Button("Clear filter") { search = "" }.font(BenchTheme.body) }
                Spacer(minLength: 0)
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Table(filteredEntries, selection: $selection) {
                TableColumn("Name") { entry in
                    HStack(spacing: 9) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                            .foregroundStyle(entry.isDirectory ? BenchTheme.transfer : BenchTheme.secondary).frame(width: 18)
                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                    }.font(BenchTheme.body).frame(minHeight: 31).help(entry.path)
                }
                TableColumn("Size") { entry in
                    Text(sizeLabel(entry)).font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                        .monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                }.width(min: 70, ideal: 86, max: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .scrollContentBackground(.hidden)
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let entry = model.entries.first(where: { $0.id == id }) {
                    if entry.isDirectory { Button("Open folder") { activate(entry) } }
                    Button("Open on Hugging Face") { open(entry) }
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fileURL(entry).absoluteString, forType: .string)
                    }
                    if !entry.isDirectory {
                        Divider()
                        Button("Delete file…", role: .destructive) { pendingDelete = entry }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first, let entry = model.entries.first(where: { $0.id == id }) { activate(entry) }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(search.isEmpty ? "\(model.entries.count) \(model.entries.count == 1 ? "item" : "items")" : "\(filteredEntries.count) of \(model.entries.count) items")
            Spacer()
            Label("Upload destination", systemImage: "arrow.down.to.line")
        }.font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
            .padding(.horizontal, 24).frame(height: BenchTheme.footerHeight)
    }
    private var rule: some View { Rectangle().fill(BenchTheme.divider).frame(height: 1) }
    private var shortName: String { repo.name.split(separator: "/").last.map(String.init) ?? repo.name }
    private var filteredEntries: [RemoteEntry] { model.entries.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    private func sizeLabel(_ entry: RemoteEntry) -> String {
        guard !entry.isDirectory, let size = entry.size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    private func goUp() {
        let parent = model.remotePath.split(separator: "/").dropLast().joined(separator: "/")
        Task { await model.browse(repo, path: parent) }
    }
    private func fileURL(_ entry: RemoteEntry) -> URL {
        repo.url.appendingPathComponent(entry.isDirectory ? "tree/main" : "blob/main").appendingPathComponent(entry.path)
    }
    private func activate(_ entry: RemoteEntry) {
        if entry.isDirectory { Task { await model.browse(repo, path: entry.path) } }
        else { open(entry) }
    }
    private func open(_ entry: RemoteEntry) { NSWorkspace.shared.open(fileURL(entry)) }
}
