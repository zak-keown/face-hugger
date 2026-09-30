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
        let repo = model.repos.first { $0.name == name && $0.kind == kind } ?? HubRepo(name: name, kind: kind)
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
