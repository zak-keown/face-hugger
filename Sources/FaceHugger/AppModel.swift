import AppKit
import SwiftUI
import UserNotifications

@MainActor @Observable
final class AppModel {
    var jobs: [UploadJob] = []
    var repos: [HubRepo] = []
    var identity: HubIdentity?
    var selectedOwner = ""
    var entries: [RemoteEntry] = []
    var remotePath = ""
    var currentRepo: HubRepo?
    var loading = false
    var accountBusy = false
    var error: String?
    var showSettings = false
    var showUpload = false
    var showCreateRepo = false
    var draftSource = ""
    var draftIncludes: [String] = []
    var draftExcludes = [".DS_Store", "**/.DS_Store"]
    var staging: StagingResult?
    var scanning = false
    var scanError: String?
    var pairings: [SavedPairing] = []
    var submitting = false
    private var scanGeneration = UUID()
    private var scanProcess: CommandProcess?
    private let pairingArchive = PairingArchive(url: AppPaths.support.appendingPathComponent("pairings.json"))
    var selectedJobID: UUID?
    var sidebar = "uploads"
    var runtimeReady = FileManager.default.isExecutableFile(atPath: AppPaths.python) && FileManager.default.fileExists(atPath: AppPaths.runtimeMarker.path)
    var installing = false
    var setupLog = ""
    var logs: [UUID: String] = [:]
    var progress: [UUID: UploadProgress] = [:]
    var keepAwake = true
    private var queueControl = UploadQueueControl()
    private var token: String?
    private var runner: CommandProcess?
    private var activity: NSObjectProtocol?
    private var browseGeneration = UUID()
    private var selectionGeneration = UUID()
    private var repoRefreshGeneration = UUID()
    private var newlyCreatedRepos: [String: (repo: HubRepo, date: Date)] = [:]
    private let archive = QueueArchive(url: AppPaths.support.appendingPathComponent("queue.json"))
    var activeJob: UploadJob? { jobs.first { $0.state == .running } }
    var selectedJob: UploadJob? { jobs.first { $0.id == selectedJobID } }
    var hasExistingCredentials: Bool {
        let env = ProcessInfo.processInfo.environment
        let tokenFile = env["HF_TOKEN_PATH"] ?? (env["HF_HOME"] ?? NSHomeDirectory() + "/.cache/huggingface") + "/token"
        return token != nil || env["HF_TOKEN"] != nil || FileManager.default.fileExists(atPath: tokenFile)
    }

    init() {
        token = CredentialStore.read()
        do { pairings = try pairingArchive.load() } catch { self.error = "Could not load saved pairings: \(error.localizedDescription)" }
        do { jobs = try archive.load() } catch { self.error = "Could not read the saved upload queue: \(error.localizedDescription)" }
    }
    func persist() {
        do { try archive.save(jobs) } catch { self.error = "Could not save the queue: \(error.localizedDescription)" }
    }
    func connect(token entered: String? = nil) async {
        guard runtimeReady else { showSettings = true; return }
        accountBusy = true; defer { accountBusy = false }
        do {
            let candidate = entered?.trimmingCharacters(in: .whitespacesAndNewlines) ?? token
            let result: HubIdentity = try await HubService.request(["whoami"], token: candidate)
            if let entered, !entered.isEmpty { try CredentialStore.save(candidate ?? ""); token = candidate }
            identity = result
            selectedOwner = result.name
            await refreshRepos()
        } catch { self.error = error.localizedDescription }
    }
    func disconnect() {
        guard activeJob == nil else { error = "Stop the active upload before signing out."; return }
        do { try CredentialStore.save(""); selectionGeneration = UUID(); browseGeneration = UUID(); repoRefreshGeneration = UUID(); loading = false; token = nil; identity = nil; repos = []; entries = []; currentRepo = nil }
        catch { self.error = error.localizedDescription }
    }
    func refreshRepos(owner: String? = nil) async {
        guard let owner = owner ?? (selectedOwner.isEmpty ? identity?.name : selectedOwner) else { return }
        let generation = UUID(); repoRefreshGeneration = generation
        loading = true; defer { if repoRefreshGeneration == generation { loading = false } }
        do {
            let result: [RepoResponse] = try await HubService.request(["repos", "--owner", owner], token: token)
            guard repoRefreshGeneration == generation else { return }
            var received = result.map(\.repo)
            let ids = Set(received.map(\.id))
            // HF's search-backed listings can lag behind successful creation.
            newlyCreatedRepos = newlyCreatedRepos.filter { !ids.contains($0.key) && Date().timeIntervalSince($0.value.date) < 120 }
            received += newlyCreatedRepos.values.map(\.repo).filter { $0.name.hasPrefix(owner + "/") }
            repos = received.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { if repoRefreshGeneration == generation { self.error = error.localizedDescription } }
    }
    func browse(_ repo: HubRepo, path: String = "", allowMissing: Bool = false) async {
        selectionGeneration = UUID()
        let generation = UUID(); browseGeneration = generation
        currentRepo = repo; remotePath = path; entries = []; loading = true
        do {
            var arguments = ["tree", "--repo", repo.name, "--type", repo.kind.rawValue, "--path", path]
            if allowMissing { arguments.append("--allow-missing-path") }
            let result: [RemoteEntry] = try await HubService.request(arguments, token: token)
            guard browseGeneration == generation else { return }
            entries = result.sorted { a, b in a.isDirectory == b.isDirectory ? a.path.localizedStandardCompare(b.path) == .orderedAscending : a.isDirectory }
        } catch { if browseGeneration == generation { self.error = error.localizedDescription } }
        if browseGeneration == generation { loading = false }
    }
    func createRepo(name: String, kind: RepoKind, isPrivate: Bool) async {
        loading = true; defer { loading = false }
        do {
            let response: RepoResponse = try await HubService.request(["create", "--repo", name, "--type", kind.rawValue, "--private", String(isPrivate)], token: token)
            newlyCreatedRepos[response.repo.id] = (response.repo, Date())
            selectedOwner = String(name.split(separator: "/")[0])
            await refreshRepos(); sidebar = response.repo.id; await browse(response.repo); showCreateRepo = false
        } catch { self.error = error.localizedDescription }
    }
    func delete(_ entry: RemoteEntry, from repo: HubRepo) async {
        guard !entry.isDirectory else { return }
        do {
            let _: [String: String] = try await HubService.request(["delete", "--repo", repo.name, "--type", repo.kind.rawValue, "--path", entry.path], token: token)
            if currentRepo == repo { await browse(repo, path: remotePath) }
        } catch { self.error = error.localizedDescription }
    }
    func chooseFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Choose folder"
        if panel.runModal() == .OK, let url = panel.url { stageFolder(url) }
    }

    func stageFolder(_ url: URL) {
        var directory: ObjCBool = false
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            error = "Choose a local folder to upload."; return
        }
        draftSource = url.path
        scanSource()
    }
    func scanSource() {
        scanProcess?.stop(); scanGeneration = UUID()
        staging = nil; scanError = nil; scanning = false
        guard !draftSource.isEmpty else { return }
        guard runtimeReady else { scanError = "Set up upload tools to preview this folder."; return }
        let generation = scanGeneration
        let process = CommandProcess(maxLineBytes: 16_000_000); scanProcess = process; scanning = true
        var args = ["scan", "--source", draftSource]
        for pattern in draftIncludes { args += ["--include", pattern] }
        for pattern in draftExcludes { args += ["--exclude", pattern] }
        Task {
            do {
                let result: StagingResult = try await HubService.request(args, token: nil, process: process)
                guard generation == scanGeneration else { return }
                staging = result
            } catch {
                guard generation == scanGeneration else { return }
                scanError = error.localizedDescription
            }
            if generation == scanGeneration { scanning = false; scanProcess = nil }
        }
    }
    func selectRepo(_ repo: HubRepo, path: String = "") async {
        // Stored visibility can change remotely. Refresh it whenever a destination is selected.
        let generation = UUID(); selectionGeneration = generation; browseGeneration = UUID()
        currentRepo = nil; remotePath = ""; entries = []; loading = true
        defer { if selectionGeneration == generation { loading = false } }
        do {
            let result: RepoResponse = try await HubService.request(["info", "--repo", repo.name, "--type", repo.kind.rawValue], token: token)
            guard selectionGeneration == generation else { return }
            await browse(result.repo, path: path, allowMissing: true)
        } catch { if selectionGeneration == generation { self.error = error.localizedDescription } }
    }
    func applyPairing(_ pairing: SavedPairing) async {
        draftSource = pairing.source; draftIncludes = pairing.includes; draftExcludes = pairing.excludes
        scanSource()
        await selectRepo(pairing.repo, path: pairing.destination)
    }
    func savePairing(name: String) {
        guard let repo = currentRepo, !draftSource.isEmpty else { return }
        let pairing = SavedPairing(name: name.trimmingCharacters(in: .whitespacesAndNewlines), source: draftSource, repo: repo, destination: remotePath, includes: draftIncludes, excludes: draftExcludes)
        guard !pairing.name.isEmpty else { return }
        var updated = pairings; updated.append(pairing)
        do { try pairingArchive.save(updated); pairings = updated } catch { self.error = error.localizedDescription }
    }
    func removePairing(_ id: UUID) {
        let updated = pairings.filter { $0.id != id }
        do { try pairingArchive.save(updated); pairings = updated } catch { self.error = error.localizedDescription }
    }
    func submitStaged(start: Bool) async {
        guard !submitting, !scanning, let staging, staging.includedCount > 0, let repo = currentRepo else { return }
        let source = draftSource, destination = remotePath, includes = draftIncludes, excludes = draftExcludes
        let scan = scanGeneration, selection = selectionGeneration
        if let problem = UploadValidation.error(source: source, repo: repo.name, destination: destination) { error = problem; return }
        submitting = true; defer { submitting = false }
        do {
            let fresh: RepoResponse = try await HubService.request(["info", "--repo", repo.name, "--type", repo.kind.rawValue], token: token)
            guard source == draftSource, destination == remotePath, repo.id == currentRepo?.id,
                  includes == draftIncludes, excludes == draftExcludes, scan == scanGeneration,
                  selection == selectionGeneration, !scanning else { return }
            guard fresh.repo.isPrivate == repo.isPrivate else {
                currentRepo = fresh.repo
                error = "Repository visibility changed to \(fresh.repo.isPrivate ? "Private" : "Public"). Review the destination and upload again."; return
            }
            // The controls may have changed while the request was running; never submit a different route.
            guard source == draftSource, destination == remotePath, repo.id == currentRepo?.id,
                  includes == draftIncludes, excludes == draftExcludes else { return }
            addJob(UploadJob(source: source, repo: fresh.repo, destination: destination, includes: includes, excludes: excludes, fileCount: staging.includedCount, byteCount: staging.includedBytes), start: start)
        } catch { self.error = error.localizedDescription }
    }

    func addJob(_ job: UploadJob, start: Bool) {
        jobs.append(job); selectedJobID = job.id; sidebar = "uploads"; persist()
        if start { queueControl.start(preferredJobID: job.id); runNext() }
    }
    func resume(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state != .running else { return }
        jobs[index].state = .queued; jobs[index].message = "Ready to resume"; jobs[index].finishedAt = nil
        queueControl.start(preferredJobID: id); persist(); runNext()
    }
    func startQueue() { queueControl.start(); runNext() }
    func stop() { queueControl.stop(); runner?.stop() }
    func remove(_ id: UUID) { guard jobs.first(where: { $0.id == id })?.state != .running else { return }; jobs.removeAll { $0.id == id }; logs.removeValue(forKey: id); progress.removeValue(forKey: id); persist() }
    func move(from: IndexSet, to: Int) { jobs.move(fromOffsets: from, toOffset: to); persist() }
    func runNext() {
        guard runner == nil else { return }
        guard runtimeReady else { showSettings = true; return }
        guard let nextID = queueControl.beginNext(in: jobs), let index = jobs.firstIndex(where: { $0.id == nextID }) else { return }
        let job = jobs[index]
        if let problem = UploadValidation.error(source: job.source, repo: job.repo.name, destination: job.destination) {
            jobs[index].state = queueControl.finish(job.id, exitStatus: -1) ?? .failed
            jobs[index].message = problem; persist(); return
        }
        jobs[index].state = .running; jobs[index].message = "Starting upload…"; persist()
        progress.removeValue(forKey: job.id)
        if keepAwake { activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Uploading files to Hugging Face") }
        let command = CommandProcess(); runner = command
        let collector = LineCollector(limit: 600)
        var args = [AppPaths.bridge, "upload", "--repo", job.repo.name, "--type", job.repo.kind.rawValue, "--source", job.source, "--destination", job.destination]
        for pattern in job.includes { args += ["--include", pattern] }
        for pattern in job.excludes { args += ["--exclude", pattern] }
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        Task {
            var status: Int32 = -1
            do {
                status = try await command.run(executable: AppPaths.python, arguments: args, token: token) { line in
                    collector.append(line)
                    Task { @MainActor in self.receive(line, jobID: job.id) }
                }
            } catch { receiveError(error.localizedDescription, jobID: job.id) }
            // Replay the bounded output in order before finalization. Queued UI callbacks
            // cannot otherwise be assumed to arrive before process termination.
            logs[job.id] = ""
            for line in collector.lines() { receive(line, jobID: job.id) }
            finish(job.id, status: status)
        }
    }
    private func receiveError(_ message: String, jobID: UUID) {
        if let index = jobs.firstIndex(where: { $0.id == jobID }) { jobs[index].message = message }
    }
    private func receive(_ line: String, jobID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }), jobs[index].state == .running else { return }
        var display = line
        if let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            display = object["message"] as? String ?? ""
            if object["event"] as? String == "progress", let reported = try? JSONDecoder().decode(UploadProgress.self, from: data) {
                progress[jobID] = reported; jobs[index].fileCount = reported.total; jobs[index].message = reported.summary
            }
            if let event = object["event"] as? String, ["status", "error"].contains(event) { jobs[index].message = display }
        }
        if !display.isEmpty {
            var text = (logs[jobID] ?? "") + display + "\n"
            if text.count > 60_000 { text = String(text.suffix(60_000)) }
            logs[jobID] = text
        }
    }
    private func finish(_ id: UUID, status: Int32) {
        guard let state = queueControl.finish(id, exitStatus: status) else { return }
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        runner = nil
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = state
        switch state {
        case .stopped: jobs[index].message = "Stopped. Already committed files remain in the repo."
        case .completed: jobs[index].message = "Upload complete"; jobs[index].finishedAt = Date()
        case .failed: if jobs[index].message == "Starting upload…" { jobs[index].message = "Upload failed. Inspect the log and resume when ready." }
        default: break
        }
        persist()
        if state == .completed, currentRepo?.id == jobs[index].repo.id {
            let repo = jobs[index].repo, path = remotePath
            Task { await browse(repo, path: path) }
        }
        let content = UNMutableNotificationContent(); content.title = state == .completed ? "Upload complete" : state == .failed ? "Upload needs attention" : "Upload stopped"; content.body = jobs[index].title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
        runNext()
    }
    func installRuntime() async {
        guard !installing else { return }
        let uv = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.local/bin/uv"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let uv else { error = "Install uv from astral.sh/uv, then choose Set up upload tools again."; return }
        guard let requirements = Bundle.main.url(forResource: "requirements", withExtension: "txt") else { error = "The app is missing its upload tool requirements."; return }
        installing = true; setupLog = "Setting up upload tools…"; defer { installing = false }
        do {
            runtimeReady = false
            if FileManager.default.fileExists(atPath: AppPaths.runtimeMarker.path) { try FileManager.default.removeItem(at: AppPaths.runtimeMarker) }
            try FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
            for args in [["venv", "--allow-existing", "--python", "3.12", AppPaths.support.appendingPathComponent("runtime").path], ["pip", "install", "--python", AppPaths.python, "-r", requirements.path]] {
                let result = try await CommandProcess().run(executable: uv, arguments: args, token: nil) { [weak self] line in
                    Task { @MainActor in self?.setupLog = String(((self?.setupLog ?? "") + "\n" + line).suffix(12_000)) }
                }
                guard result == 0 else { throw NSError(domain: "Setup", code: Int(result), userInfo: [NSLocalizedDescriptionKey: "Upload tool setup failed. See the setup log."]) }
            }
            try Data("huggingface_hub==2.0.0".utf8).write(to: AppPaths.runtimeMarker, options: .atomic)
            runtimeReady = true; setupLog += "\nUpload tools are ready."
        } catch { self.error = error.localizedDescription }
    }
}
