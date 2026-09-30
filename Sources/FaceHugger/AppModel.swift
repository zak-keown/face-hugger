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
    var selectedJobID: UUID?
    var sidebar = "uploads"
    var runtimeReady = FileManager.default.isExecutableFile(atPath: AppPaths.python) && FileManager.default.fileExists(atPath: AppPaths.runtimeMarker.path)
    var installing = false
    var setupLog = ""
    var logs: [UUID: String] = [:]
    var keepAwake = true
    var queuePaused = true
    private var token: String?
    private var runner: CommandProcess?
    private var activity: NSObjectProtocol?
    private var browseGeneration = UUID()
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
        do { try CredentialStore.save(""); token = nil; identity = nil; repos = []; entries = []; currentRepo = nil }
        catch { self.error = error.localizedDescription }
    }
    func refreshRepos(owner: String? = nil) async {
        guard let owner = owner ?? (selectedOwner.isEmpty ? identity?.name : selectedOwner) else { return }
        loading = true; defer { loading = false }
        do {
            let result: [RepoResponse] = try await HubService.request(["repos", "--owner", owner], token: token)
            repos = result.map(\.repo).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        } catch { self.error = error.localizedDescription }
    }
    func browse(_ repo: HubRepo, path: String = "") async {
        let generation = UUID(); browseGeneration = generation
        currentRepo = repo; remotePath = path; entries = []; loading = true
        do {
            let result: [RemoteEntry] = try await HubService.request(["tree", "--repo", repo.name, "--type", repo.kind.rawValue, "--path", path], token: token)
            guard browseGeneration == generation else { return }
            entries = result.sorted { a, b in a.isDirectory == b.isDirectory ? a.path.localizedStandardCompare(b.path) == .orderedAscending : a.isDirectory }
        } catch { if browseGeneration == generation { self.error = error.localizedDescription } }
        if browseGeneration == generation { loading = false }
    }
    func createRepo(name: String, kind: RepoKind, isPrivate: Bool) async {
        loading = true; defer { loading = false }
        do {
            let response: RepoResponse = try await HubService.request(["create", "--repo", name, "--type", kind.rawValue, "--private", String(isPrivate)], token: token)
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
        if panel.runModal() == .OK, let url = panel.url { draftSource = url.path; showUpload = true }
    }
    func addJob(_ job: UploadJob, start: Bool) {
        jobs.append(job); selectedJobID = job.id; sidebar = "uploads"; persist()
        if start { queuePaused = false; runNext() }
    }
    func resume(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].state != .running else { return }
        jobs[index].state = .queued; jobs[index].message = "Ready to resume"; jobs[index].finishedAt = nil
        queuePaused = false; persist(); runNext()
    }
    func startQueue() { queuePaused = false; runNext() }
    func stop() { queuePaused = true; runner?.stop() }
    func remove(_ id: UUID) { guard jobs.first(where: { $0.id == id })?.state != .running else { return }; jobs.removeAll { $0.id == id }; logs.removeValue(forKey: id); persist() }
    func move(from: IndexSet, to: Int) { jobs.move(fromOffsets: from, toOffset: to); persist() }
    func runNext() {
        guard !queuePaused, runner == nil, let index = jobs.firstIndex(where: { $0.state == .queued }) else { return }
        guard runtimeReady else { showSettings = true; return }
        let job = jobs[index]
        if let problem = UploadValidation.error(source: job.source, repo: job.repo.name, destination: job.destination) {
            jobs[index].state = .failed; jobs[index].message = problem; persist(); queuePaused = true; return
        }
        jobs[index].state = .running; jobs[index].message = "Starting upload…"; persist()
        if keepAwake { activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: "Uploading files to Hugging Face") }
        let command = CommandProcess(); runner = command
        let collector = LineCollector(limit: 600)
        var args = [AppPaths.bridge, "upload", "--repo", job.repo.name, "--type", job.repo.kind.rawValue, "--source", job.source, "--destination", job.destination]
        for pattern in job.includes { args += ["--include", pattern] }
        for pattern in job.excludes { args += ["--exclude", pattern] }
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
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
            if let event = object["event"] as? String, ["status", "error"].contains(event) { jobs[index].message = display }
        }
        if !display.isEmpty {
            var text = (logs[jobID] ?? "") + display + "\n"
            if text.count > 60_000 { text = String(text.suffix(60_000)) }
            logs[jobID] = text
        }
    }
    private func finish(_ id: UUID, status: Int32) {
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        runner = nil
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        if queuePaused { jobs[index].state = .stopped; jobs[index].message = "Stopped. Already committed files remain in the repo." }
        else if status == 0 { jobs[index].state = .completed; jobs[index].message = "Upload complete"; jobs[index].finishedAt = Date() }
        else { jobs[index].state = .failed; queuePaused = true; if jobs[index].message == "Starting upload…" { jobs[index].message = "Upload failed. Inspect the log and resume when ready." } }
        persist()
        let content = UNMutableNotificationContent(); content.title = jobs[index].state == .completed ? "Upload complete" : "Upload stopped"; content.body = jobs[index].title
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
