import SwiftUI

struct RepositoryPicker: View {
    @Bindable var model: AppModel
    var dismiss: () -> Void
    @State private var search = ""
    @State private var manual = ""
    @State private var kind: RepoKind = .model
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choose repository").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { Task { await model.refreshRepos() } } label: { Image(systemName: "arrow.clockwise") }.help("Refresh repositories")
            }
            if let identity = model.identity {
                Picker("Owner", selection: $model.selectedOwner) {
                    Text(identity.name).tag(identity.name)
                    ForEach(identity.organizations, id: \.self) { Text($0).tag($0) }
                }.onChange(of: model.selectedOwner) { _, owner in Task { await model.refreshRepos(owner: owner) } }
            }
            TextField("Find a repository", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.repos.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { repo in
                        Button { dismiss(); Task { await model.selectRepo(repo) } } label: {
                            HStack(spacing: 10) {
                                Image(systemName: repo.kind == .model ? "cube" : "square.stack.3d.up")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(repo.name).font(.system(size: 13, weight: .medium))
                                    Text("\(repo.kind.rawValue.capitalized) · \(repo.isPrivate ? "Private" : "Public")").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if repo.isPrivate { Image(systemName: "lock") }
                            }.padding(8).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if model.repos.isEmpty { Text(model.loading ? "Loading repositories…" : "No repositories found for this owner.").font(.system(size: 13)).foregroundStyle(.secondary).padding(8) }
                }
            }.frame(height: 220)
            Divider()
            Text("Open by repository ID").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("owner/repository", text: $manual).textFieldStyle(.roundedBorder)
            HStack {
                Picker("Type", selection: $kind) { Text("Model").tag(RepoKind.model); Text("Dataset").tag(RepoKind.dataset) }.labelsHidden()
                Button("Open") { let repo = HubRepo(name: manual.trimmingCharacters(in: .whitespacesAndNewlines), kind: kind); dismiss(); Task { await model.selectRepo(repo) } }.disabled(manual.split(separator: "/").count != 2)
            }
            Divider()
            Button("New repository…", systemImage: "plus") { dismiss(); model.showCreateRepo = true }
        }.padding(20).frame(width: 380)
    }
}

struct FilterEditor: View {
    @Bindable var model: AppModel
    var dismiss: () -> Void
    @State private var includes = ""
    @State private var excludes = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File filters").font(.system(size: 16, weight: .semibold))
            Text("Include").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("All files", text: $includes, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Include patterns")
                .accessibilityHint("One glob pattern per line. Leave blank to include all files.")
            Text("Exclude").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("No additional exclusions", text: $excludes, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Exclude patterns")
                .accessibilityHint("One glob pattern per line. Matching files are excluded from the upload.")
            Text(verbatim: "One glob per line. For example: *.safetensors or **/logs/**. Git metadata and the HF upload cache are always ignored.").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply filters") { model.draftIncludes = patterns(includes); model.draftExcludes = patterns(excludes); model.scanSource(); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 350)
            .onAppear { includes = model.draftIncludes.joined(separator: "\n"); excludes = model.draftExcludes.joined(separator: "\n") }
    }
    private func patterns(_ value: String) -> [String] { value.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

struct DestinationSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var problem: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Folder in repository").font(.system(size: 20, weight: .semibold))
            Text(model.currentRepo?.name ?? "").foregroundStyle(.secondary)
            TextField("Root of repository", text: $path).textFieldStyle(.roundedBorder)
            Text("Leave blank for the root. A new folder appears when its files are uploaded.").font(.system(size: 12)).foregroundStyle(.secondary)
            if let problem { Text(problem).font(.system(size: 13)).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use folder") {
                    let candidate = path.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !candidate.hasPrefix("/"), !candidate.contains("\\"), !candidate.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }), candidate.rangeOfCharacter(from: .controlCharacters) == nil else { problem = "Use a relative path without '.' or '..'."; return }
                    if let repo = model.currentRepo { Task { await model.browse(repo, path: candidate, allowMissing: true) } }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 440).onAppear { path = model.remotePath }
    }
}
