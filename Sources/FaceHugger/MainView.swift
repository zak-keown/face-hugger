import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainView: View {
    @Bindable var model: AppModel
    @State private var search = ""
    @State private var dropTarget = false
    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 225, max: 280)
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    if model.sidebar == "uploads" || model.sidebar == "history" { queue }
                    else if let repo = model.currentRepo { RepoBrowser(model: model, repo: repo) }
                    else { ContentUnavailableView("Choose a repository", systemImage: "folder", description: Text("Your model and dataset repositories appear in the sidebar.")) }
                }.frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
                if (model.sidebar == "uploads" || model.sidebar == "history"), let job = model.selectedJob {
                    JobInspector(model: model, job: job).frame(minWidth: 265, idealWidth: 300, maxWidth: 360)
                }
            }
        }
        .frame(minWidth: 880, minHeight: 560)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) { Text(model.sidebar == "history" ? "Upload history" : model.sidebar == "uploads" ? "Uploads" : model.currentRepo?.name ?? "Repositories").font(.headline) }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.activeJob != nil { Button("Stop", systemImage: "stop.circle") { model.stop() } }
                Button("New Upload", systemImage: "plus") { model.chooseFolder() }.help("Upload a local folder (⌘N)")
            }
        }
        .overlay { if dropTarget { RoundedRectangle(cornerRadius: 12).strokeBorder(.yellow, lineWidth: 4).padding(5).allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.isFileURL else { return false }
            model.draftSource = url.path; model.showUpload = true; return true
        } isTargeted: { dropTarget = $0 }
        .sheet(isPresented: $model.showUpload) { UploadSheet(model: model) }
        .sheet(isPresented: $model.showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $model.showCreateRepo) { CreateRepoSheet(model: model) }
        .alert("Face Hugger", isPresented: Binding(get: { model.error != nil && !model.showSettings && !model.showCreateRepo && !model.showUpload }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task { if model.runtimeReady && model.hasExistingCredentials { await model.connect() } }
    }
    private var sidebar: some View {
        VStack(spacing: 0) {
            if let identity = model.identity, !identity.organizations.isEmpty {
                Picker("Owner", selection: $model.selectedOwner) {
                    Text(identity.name).tag(identity.name)
                    ForEach(identity.organizations, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().padding(.horizontal, 14).padding(.top, 10)
                    .onChange(of: model.selectedOwner) { _, owner in Task { await model.refreshRepos(owner: owner) } }
            }
            List(selection: $model.sidebar) {
                Section {
                    Label("Uploads", systemImage: "tray.and.arrow.up").badge(model.jobs.filter { $0.state != .completed }.count).tag("uploads")
                    Label("History", systemImage: "clock").tag("history")
                }
                Section {
                    ForEach(model.repos.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { repo in
                        HStack(spacing: 7) {
                            Image(systemName: repo.kind == .model ? "cube" : "square.stack.3d.up").foregroundStyle(.secondary)
                            Text(repo.name.split(separator: "/").last.map(String.init) ?? repo.name).lineLimit(1)
                            if repo.isPrivate { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.tertiary) }
                        }.tag(repo.id).help(repo.name)
                    }
                    if model.identity != nil {
                        Button("New repository…", systemImage: "folder.badge.plus") { model.showCreateRepo = true }.buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                } header: {
                    HStack {
                        Text("Repositories")
                        Spacer()
                        if model.loading { ProgressView().controlSize(.mini) }
                        else { Button { Task { await model.refreshRepos() } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("Refresh repositories") }
                    }
                }
            }
            .searchable(text: $search, placement: .sidebar, prompt: "Find a repository")
            .onChange(of: model.sidebar) { _, value in
                if let repo = model.repos.first(where: { $0.id == value }) { Task { await model.browse(repo) } }
            }
            Divider()
            Button { model.showSettings = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.identity?.name ?? "Connect your account").font(.callout.weight(.medium))
                        Text(model.runtimeReady ? "Hugging Face" : "Set up upload tools").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "gearshape").foregroundStyle(.secondary)
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
    }
    private var visibleJobs: [UploadJob] { model.jobs.filter { model.sidebar == "history" ? $0.state == .completed : $0.state != .completed } }
    private var queue: some View {
        VStack(spacing: 0) {
            if visibleJobs.isEmpty {
                Spacer()
                Image("Hugger").resizable().scaledToFit().frame(width: 160, height: 160).accessibilityHidden(true)
                Text(model.sidebar == "history" ? "Good things take a little uploading." : "A little help with big uploads.").font(.title2.weight(.semibold)).padding(.top, 16)
                Text(model.sidebar == "history" ? "Completed uploads will be waiting here." : "Drop a folder here. We’ll take it from there.")
                    .foregroundStyle(.secondary).padding(.top, 5)
                Button(model.runtimeReady ? "Choose a folder…" : "Get started") {
                    if model.runtimeReady { model.chooseFolder() } else { model.showSettings = true }
                }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 18)
                Spacer()
            } else {
                HStack {
                    Text(model.sidebar == "history" ? "Completed" : "Your upload queue").font(.title3.weight(.semibold))
                    Spacer()
                    if model.activeJob == nil && model.jobs.contains(where: { $0.state == .queued }) {
                        Button("Start queue", systemImage: "play.fill") { model.startQueue() }.buttonStyle(.bordered)
                    }
                }.padding(20)
                List(selection: $model.selectedJobID) {
                    ForEach(visibleJobs) { job in
                        JobRow(job: job).tag(job.id).padding(.vertical, 8)
                            .contextMenu {
                                if job.state != .running && job.state != .completed { Button(job.state == .queued ? "Start upload" : "Resume upload") { model.resume(job.id) } }
                                Button("Reveal in Finder") { NSWorkspace.shared.selectFile(job.source, inFileViewerRootedAtPath: "") }
                                Button("Open on Hugging Face") { NSWorkspace.shared.open(job.repo.url) }
                                if job.state != .running { Button("Remove from queue", role: .destructive) { model.remove(job.id) } }
                            }
                    }
                    .onMove { indices, destination in
                        var ordered = visibleJobs
                        ordered.move(fromOffsets: indices, toOffset: destination)
                        let ids = Set(ordered.map(\.id)); var iterator = ordered.makeIterator()
                        model.jobs = model.jobs.map { ids.contains($0.id) ? iterator.next()! : $0 }; model.persist()
                    }
                }.listStyle(.inset)
            }
            Divider()
            HStack(spacing: 7) {
                Image(systemName: model.activeJob != nil ? "arrow.up.circle.fill" : "checkmark.circle").foregroundStyle(model.activeJob != nil ? .orange : .secondary)
                Text(model.activeJob != nil ? "Uploads continue when you close this window" : "\(visibleJobs.count) \(model.sidebar == "history" ? "completed " : "")\(visibleJobs.count == 1 ? "upload" : "uploads")")
                Spacer()
                if model.activeJob != nil && model.keepAwake { Image(systemName: "sun.max").help("Keeping your Mac awake while uploading") }
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 11)
        }
    }
}

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
                if !job.includes.isEmpty { detail("Include", job.includes.joined(separator: "\n")) }
                if !job.excludes.isEmpty { detail("Exclude", job.excludes.joined(separator: "\n")) }
                Divider()
                if job.state == .running {
                    Text("Hugging Face prepares, transfers, and commits files. Detailed activity appears in the log; an exact overall percentage isn’t available.").font(.caption).foregroundStyle(.secondary)
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
