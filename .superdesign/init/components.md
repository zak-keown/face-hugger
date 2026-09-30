# Shared native components

Framework: Swift 6, SwiftUI, and AppKit; macOS 15 minimum. XcodeGen builds the application. No React, HTML, CSS, Tailwind, or third-party UI component library. Components share the app module, so dependencies are symbol references rather than relative imports. Standard Button, TextField, SecureField, Picker, Form, List, Table, ProgressView, DisclosureGroup, and ContentUnavailableView are system primitives, with no custom wrappers.

## ErrorBanner
- Source: `Sources/FaceHugger/Sheets.swift`
- Description: Shared inline, dismissible error presentation in all three sheets.
- Inputs: model: AppModel; reads error and clears it on dismissal

```swift
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

## JobRow
- Source: `Sources/FaceHugger/MainView.swift`
- Description: Shared upload row used by the queue and history.
- Inputs: job: UploadJob

```swift
struct JobRow: View {
    let job: UploadJob
    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "folder.fill").font(.system(size: 30)).foregroundStyle(Color(red: 0.33, green: 0.64, blue: 0.83)).padding(.top, 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(job.title).font(.headline); Spacer(); Text(job.state.label).font(.caption.weight(.medium)).foregroundStyle(color) }
                Text(job.repo.name + (job.destination.isEmpty ? "" : " / \(job.destination)")).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                if job.state == .running { ProgressView().progressViewStyle(.linear).tint(.yellow) }
                Text(job.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.padding(.vertical, 4)
    }
    private var color: Color { switch job.state { case .completed: .green; case .failed: .red; case .running: .orange; default: .secondary } }
}
```

## JobInspector
- Source: `Sources/FaceHugger/MainView.swift`
- Description: Detail inspector shared by selected queue and history jobs.
- Inputs: model: AppModel; job: UploadJob; internal showLog toggle

```swift
struct JobInspector: View {
    @Bindable var model: AppModel
    let job: UploadJob
    @State private var showLog = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Upload details").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text(job.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                    Label(job.state.label, systemImage: job.state == .completed ? "checkmark.circle.fill" : "arrow.up.circle").foregroundStyle(.secondary)
                }
                detail("From", job.source)
                detail("To", job.repo.name + "/" + job.destination)
                detail("Repository", "\(job.repo.kind.rawValue.capitalized) · \(job.repo.isPrivate ? "Private" : "Visibility set on Hugging Face")")
                detail("Added", job.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let finished = job.finishedAt { detail("Completed", finished.formatted(date: .abbreviated, time: .shortened)) }
                if !job.includes.isEmpty { detail("Include", job.includes.joined(separator: "\n")) }
                if !job.excludes.isEmpty { detail("Exclude", job.excludes.joined(separator: "\n")) }
                Divider()
                if job.state != .completed, let progress = model.progress[job.id] {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(job.state == .running ? "Live activity" : "Last reported activity").font(.caption).foregroundStyle(.secondary)
                        LabeledContent("Prepared", value: "\(progress.checked) of \(progress.total) files")
                        LabeledContent("Uploaded or reused", value: "\(progress.uploaded) of \(progress.uploadTotal) files")
                        LabeledContent("Data sent", value: progress.transferred)
                        LabeledContent("Committed", value: "\(progress.committed) files")
                        LabeledContent("Commits", value: "\(progress.commits)")
                    }.font(.caption).monospacedDigit()
                }
                if job.state == .running {
                    Text("Preparation, transfer, and commits overlap. Already-uploaded content may be reused; only files needing transfer count toward that stage.").font(.caption).foregroundStyle(.secondary)
                    Button("Stop uploads", systemImage: "stop.circle") { model.stop() }
                } else if job.state != .completed {
                    Button(job.state == .queued ? "Start upload" : "Resume upload", systemImage: "play.fill") { model.resume(job.id) }.buttonStyle(.borderedProminent)
                    Text("Resume checks the source again. Keep its files unchanged to continue the same upload.").font(.caption).foregroundStyle(.secondary)
                }
                Button("Open on Hugging Face", systemImage: "arrow.up.right.square") { NSWorkspace.shared.open(job.repo.url) }
                Button("Reveal in Finder", systemImage: "folder") { NSWorkspace.shared.selectFile(job.source, inFileViewerRootedAtPath: "") }
                DisclosureGroup("Activity log", isExpanded: $showLog) {
                    Text(model.logs[job.id] ?? "Logs appear here while this upload runs. Logs aren’t retained after quitting.")
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
            }.padding(22)
        }.background(.background.secondary)
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
}
```

## MenuContent
- Source: `Sources/FaceHugger/FaceHuggerApp.swift`
- Description: Persistent menu bar surface with active upload and window controls.
- Inputs: model: AppModel; openWindow environment action

```swift
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

