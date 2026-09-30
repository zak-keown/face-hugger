import SwiftUI

struct DatasetCardSheet: View {
    @Bindable var workspace: DatasetCardWorkspace
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var compare = false
    @State private var pendingModel: Bool?
    @State private var confirmClose = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dataset card").font(BenchTheme.title)
                    Text(workspace.repository ?? workspace.access.url.lastPathComponent)
                        .font(BenchTheme.body).foregroundStyle(BenchTheme.secondary).lineLimit(1)
                }
                Spacer()
                Text("README.md").font(.system(size: 13, design: .monospaced)).foregroundStyle(BenchTheme.secondary)
            }.padding(24).background(BenchTheme.remote)
            rule
            HStack(spacing: 0) {
                context.frame(width: 300)
                Rectangle().fill(BenchTheme.divider).frame(width: 1)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            rule
            HStack(spacing: 12) {
                Button("Close") { requestClose() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("Save locally, then upload when ready.")
                    .font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                Button { workspace.save(onSaved: onSaved) } label: {
                    Text("Save README as…").font(BenchTheme.body.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(BenchTheme.actionInk)
                        .background(BenchTheme.gold, in: RoundedRectangle(cornerRadius: 7))
                        .opacity(workspace.busy || workspace.markdown.isEmpty ? 0.45 : 1)
                }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.plain)
                    .disabled(workspace.busy || workspace.markdown.isEmpty)
            }.padding(.horizontal, 24).padding(.vertical, 16).background(BenchTheme.source)
        }
        .foregroundStyle(BenchTheme.ink)
        .frame(width: 1020, height: 730)
        .interactiveDismissDisabled(workspace.isDirty || workspace.busy)
        .task { workspace.load() }
        .onDisappear { workspace.cancel() }
        .confirmationDialog("Replace the text in this draft?", isPresented: Binding(get: { pendingModel != nil }, set: { if !$0 { pendingModel = nil } })) {
            Button("Replace draft") {
                if let useModel = pendingModel { workspace.compose(useModel: useModel) }
                pendingModel = nil
            }
            Button("Cancel", role: .cancel) { pendingModel = nil }
        } message: { Text("Your current editor text will be replaced. The saved README stays unchanged until you save.") }
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmClose) {
            Button("Discard changes", role: .destructive) { workspace.cancel(); dismiss() }
            Button("Keep editing", role: .cancel) { }
        } message: { Text("The draft has not been saved. Your existing files are unchanged.") }
    }

    private var rule: some View { Rectangle().fill(BenchTheme.divider).frame(height: 1) }

    private var context: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("From your folder", systemImage: "folder").font(BenchTheme.section)
                    Text(workspace.access.url.lastPathComponent).font(BenchTheme.body).lineLimit(2)
                    if let facts = workspace.facts {
                        Text("\(facts.includedCount) files · \(ByteCountFormatter.string(fromByteCount: facts.includedBytes, countStyle: .file))")
                            .font(BenchTheme.body).monospacedDigit()
                        Text("\(facts.excludedCount) excluded by your filters. Snapshot taken when this editor opened; file contents are not read for drafting.")
                            .font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                    } else if workspace.busy {
                        HStack { ProgressView().controlSize(.small); Text("Measuring folder…").font(BenchTheme.body) }
                    }
                    if !workspace.destination.isEmpty {
                        Text("Files target /\(workspace.destination). A dataset card belongs at the repository root.")
                            .font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                    }
                }
                rule
                field("Dataset name", text: $workspace.input.title, prompt: "A descriptive name")
                field("What is it for?", text: $workspace.input.purpose, prompt: "Describe the data and its intended use", multiline: true)
                field("Where did it come from?", text: $workspace.input.provenance, prompt: "Source and collection process", multiline: true)
                field("License", text: $workspace.input.license, prompt: "Enter the license you have chosen")
                field("Known limitations", text: $workspace.input.limitations, prompt: "Coverage, quality, or uses to avoid", multiline: true)
                Text("Leave unknowns blank. They stay marked TODO in the card.")
                    .font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                rule
                VStack(alignment: .leading, spacing: 10) {
                    if workspace.generating {
                        HStack { ProgressView().controlSize(.small); Text("Drafting on this Mac…").font(BenchTheme.body) }
                        Button("Cancel drafting") { workspace.cancel() }
                    } else {
                        Button("Draft on this Mac", systemImage: "sparkles") { requestCompose(useModel: true) }
                            .disabled(workspace.busy || workspace.facts == nil || workspace.availabilityReason != nil || workspace.input.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Use template", systemImage: "doc.text") { requestCompose(useModel: false) }
                            .disabled(workspace.busy || workspace.facts == nil)
                    }
                    if workspace.input.purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Add a purpose above to enable on-device drafting.").font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                    }
                    Text(workspace.availabilityReason ?? "Apple Intelligence writes the overview on this Mac. Your notes and file metadata stay on device.")
                        .font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary)
                    if workspace.availabilityReason != nil {
                        Button("Check availability") { workspace.availabilityReason = DatasetCardGenerator.availabilityReason }
                            .font(BenchTheme.metadata)
                    }
                }
            }.padding(22)
        }.background(BenchTheme.source)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(BenchTheme.body.weight(.medium))
            TextField(prompt, text: text, axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 2...4 : 1...1)
                .textFieldStyle(.roundedBorder).font(BenchTheme.body)
                .accessibilityLabel(title)
                .disabled(workspace.busy)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Review your card").font(BenchTheme.section)
                Spacer()
                if workspace.hasExistingCard {
                    Picker("View", selection: $compare) {
                        Text("Edit").tag(false)
                        Text("Changes").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 160)
                }
            }.padding(.horizontal, 22).frame(height: 48)
            rule
            if compare {
                HStack(alignment: .top, spacing: 0) {
                    comparisonColumn("Original local README", text: workspace.original)
                    Rectangle().fill(BenchTheme.divider).frame(width: 1)
                    comparisonColumn("Current draft", text: workspace.markdown)
                }
            } else {
                TextEditor(text: $workspace.markdown)
                    .font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(16)
                    .accessibilityLabel("Dataset card Markdown")
                    .disabled(workspace.busy)
            }
            if workspace.notesNeedApplying {
                rule
                Text("Notes changed. Use template or Draft on this Mac to apply them to the card.")
                    .font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary).padding(12)
            }
            if let error = workspace.error {
                rule
                Label(error, systemImage: "exclamationmark.circle")
                    .font(BenchTheme.body).textSelection(.enabled).padding(16)
                if workspace.facts == nil, !workspace.busy {
                    Button("Try again") { workspace.error = nil; workspace.load() }.padding(.horizontal, 16).padding(.bottom, 12)
                }
            } else if let notice = workspace.notice {
                rule
                Text(notice).font(BenchTheme.metadata).foregroundStyle(BenchTheme.secondary).padding(16)
            }
        }.background(BenchTheme.remote)
    }

    private func comparisonColumn(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(BenchTheme.metadata.weight(.semibold)).foregroundStyle(BenchTheme.secondary)
            ScrollView {
                Text(text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func requestCompose(useModel: Bool) {
        if workspace.hasExistingCard || workspace.isDirty { pendingModel = useModel }
        else { workspace.compose(useModel: useModel) }
    }
    private func requestClose() {
        if workspace.isDirty { confirmClose = true }
        else { workspace.cancel(); dismiss() }
    }
}
