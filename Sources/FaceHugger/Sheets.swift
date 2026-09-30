import AppKit
import SwiftUI

struct SettingsSheet: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Account and upload tools").font(.title2.weight(.semibold))
            Form {
                Section("Upload tools") {
                    Text("One-time setup downloads Python and Hugging Face tools. An internet connection is required; no terminal setup is needed.").font(.system(size: 12)).foregroundStyle(.secondary)
                    Label(model.runtimeReady ? "Hugging Face tools are ready" : "Set up Hugging Face tools", systemImage: model.runtimeReady ? "checkmark.circle.fill" : "shippingbox")
                    Text("Face Hugger uses an isolated Python environment for the official Hugging Face CLI. Setup requires uv and an internet connection.").font(.caption).foregroundStyle(.secondary)
                    HStack { Button(model.runtimeReady ? "Repair upload tools" : "Set up upload tools") { Task { await model.installRuntime() } }.disabled(model.installing || model.activeJob != nil); if model.installing { ProgressView().controlSize(.small) } }
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
