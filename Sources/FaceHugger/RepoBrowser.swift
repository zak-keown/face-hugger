import AppKit
import SwiftUI

struct RepoBrowser: View {
    @Bindable var model: AppModel
    let repo: HubRepo
    @State private var selection: String?
    @State private var search = ""
    @State private var pendingDelete: RemoteEntry?
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: repo.kind == .model ? "cube" : "square.stack.3d.up").font(.title).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(repo.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Text("\(repo.kind.rawValue.capitalized) repository · \(repo.isPrivate ? "Private" : "Public")").foregroundStyle(.secondary)
                }
                Spacer()
                Button { NSWorkspace.shared.open(repo.url) } label: { Image(systemName: "arrow.up.right.square") }.help("Open on Hugging Face")
                Button { Task { await model.browse(repo, path: model.remotePath) } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh")
            }.padding(22)
            HStack {
                Button { Task { await model.browse(repo) } } label: { Image(systemName: "house") }.buttonStyle(.plain).help("Repository root")
                Text("/ " + model.remotePath).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                if !model.remotePath.isEmpty {
                    Button("Up", systemImage: "arrow.up") {
                        let parent = model.remotePath.split(separator: "/").dropLast().joined(separator: "/")
                        Task { await model.browse(repo, path: parent) }
                    }
                }
                TextField("Filter files", text: $search).textFieldStyle(.roundedBorder).frame(width: 180)
            }.padding(.horizontal, 22).padding(.bottom, 14)
            Divider()
            if model.loading { Spacer(); ProgressView("Loading files…"); Spacer() }
            else if model.entries.isEmpty { ContentUnavailableView("This folder is ready for files", systemImage: "folder", description: Text("Drop a local folder here to start an upload.")) }
            else {
                Table(model.entries.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }, selection: $selection) {
                    TableColumn("Name") { entry in
                        HStack { Image(systemName: entry.isDirectory ? "folder.fill" : "doc").foregroundStyle(entry.isDirectory ? .blue : .secondary); Text(entry.name) }
                            .contextMenu {
                                if entry.isDirectory { Button("Open folder") { Task { await model.browse(repo, path: entry.path) } } }
                                else {
                                    Button("Open on Hugging Face") { open(entry) }
                                    Button("Copy link") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(fileURL(entry).absoluteString, forType: .string) }
                                    Divider()
                                    Button("Delete file…", role: .destructive) { pendingDelete = entry }
                                }
                            }
                            .onTapGesture(count: 2) { if entry.isDirectory { Task { await model.browse(repo, path: entry.path) } } else { open(entry) } }
                    }
                    TableColumn("Size") { entry in Text(entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size ?? 0, countStyle: .file)).foregroundStyle(.secondary).monospacedDigit() }.width(100)
                }
            }
            Divider()
            HStack { Text("\(model.entries.count) items"); Spacer(); Text("Drop a folder to upload here") }.font(.caption).foregroundStyle(.secondary).padding(12)
        }
        .confirmationDialog("Delete \(pendingDelete?.name ?? "file")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            if let entry = pendingDelete { Button("Delete file", role: .destructive) { Task { await model.delete(entry, from: repo) }; pendingDelete = nil } }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { Text("This creates a deletion commit on \(repo.name). It does not erase the file from the repository’s history.") }
    }
    private func fileURL(_ entry: RemoteEntry) -> URL { repo.url.appendingPathComponent("blob/main").appendingPathComponent(entry.path) }
    private func open(_ entry: RemoteEntry) { NSWorkspace.shared.open(fileURL(entry)) }
}
