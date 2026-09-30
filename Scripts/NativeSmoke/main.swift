import Foundation
import CryptoKit

private struct SmokeFailure: LocalizedError { var errorDescription: String? }
private func check(_ condition: Bool, _ message: String) throws { if !condition { throw SmokeFailure(errorDescription: message) } }
private func sha(_ url: URL) throws -> String {
    let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
    var hash = SHA256()
    while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var latest = NativeUploadProgress()
    func receive(_ event: NativeUploadEvent) { if case .progress(let value) = event { lock.withLock { latest = value } } }
    var progress: NativeUploadProgress { lock.withLock { latest } }
}
private final class StopDuringTransfer: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Error>?
    private var stopped = false
    private var observedBytes: Int64 = 0
    func attach(_ task: Task<Void, Error>) {
        let stop = lock.withLock { self.task = task; return stopped }
        if stop { task.cancel() }
    }
    func receive(_ event: NativeUploadEvent) {
        guard case .progress(let progress) = event, progress.transferredBytes >= 1024 * 1024 else { return }
        let cancel = lock.withLock { () -> Task<Void, Error>? in
            guard !stopped else { return nil }
            stopped = true; observedBytes = progress.transferredBytes
            return task
        }
        cancel?.cancel()
    }
    var bytesAtStop: Int64 { lock.withLock { observedBytes } }
}
private final class DownloadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var next = request
        if next.url?.host != "huggingface.co" { next.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(next)
    }
}
@main struct NativeSmoke {
    static func main() async {
        guard CommandLine.arguments.contains("--run-live"), let token = ProcessInfo.processInfo.environment["HF_TOKEN"], !token.isEmpty else {
            print("Explicit --run-live and HF_TOKEN are required. No mutation performed."); exit(2)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--resume-fixture"), CommandLine.arguments.indices.contains(index + 1) {
            do {
                let jobURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                let job = try JSONDecoder().decode(UploadJob.self, from: Data(contentsOf: jobURL))
                let events = Events()
                try await NativeUploader.upload(job: job, token: token, checkpointDirectory: jobURL.deletingLastPathComponent().appendingPathComponent("checkpoints"), onEvent: { events.receive($0) })
                print("RESUMED-COMMITTED:\(events.progress.committed)")
                return
            } catch { print("Fresh-process resume failed (details suppressed)."); exit(1) }
        }
        let work = URL(fileURLWithPath: ".build/native-smoke/run-" + UUID().uuidString)
        let report = URL(fileURLWithPath: ".build/native-smoke/result.json")
        let client = NativeHubClient(token: token)
        var record: [String: Any] = ["passed": false, "repoDeleted": false, "transport": "URLSession", "hashing": "CryptoKit"]
        var repo: HubRepo?, created = false
        let delegate = DownloadDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        func save() {
            if let data = try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: report, options: .atomic) }
        }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let owner = try await client.whoami().name
            let target = HubRepo(name: owner + "/face-hugger-native-app-" + UUID().uuidString.lowercased().prefix(12), kind: .dataset, isPrivate: true)
            repo = target; record["repo"] = target.name; save()
            created = true // Unique repository creation intent is recorded before the request.
            _ = try await client.create(repo: target); save()
            let listed = try await client.repos(owner: owner)
            record["repositoryListingSucceeded"] = true
            record["newRepositoryListedImmediately"] = listed.contains { $0.name == target.name }
            let source = work.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("Native upload smoke test.\n".utf8).write(to: source.appendingPathComponent("notes.txt"))
            try Data("Must remain local.\n".utf8).write(to: source.appendingPathComponent("excluded.txt"))
            let payload = source.appendingPathComponent("payload.bin")
            FileManager.default.createFile(atPath: payload.path, contents: nil)
            let file = try FileHandle(forWritingTo: payload)
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<16 {
                var data = Data(count: 1024 * 1024)
                data.withUnsafeMutableBytes { raw in
                    let words = raw.bindMemory(to: UInt64.self)
                    for index in words.indices { words[index] = generator.next() }
                }
                try file.write(contentsOf: data)
            }
            try file.close()
            let job = UploadJob(source: source.path, repo: target, destination: "native-check", excludes: ["excluded.txt"])
            let checkpoints = work.appendingPathComponent("checkpoints")
            let stop = StopDuringTransfer()
            let interrupted = Task {
                try await NativeUploader.upload(job: job, token: token, checkpointDirectory: checkpoints, onEvent: { stop.receive($0) })
            }
            stop.attach(interrupted)
            do {
                try await interrupted.value
                throw SmokeFailure(errorDescription: "Upload finished before cancellation was exercised")
            } catch is CancellationError {
                try check(stop.bytesAtStop > 0 && stop.bytesAtStop < 16 * 1024 * 1024, "Cancellation did not interrupt an active file transfer")
                record["cancelledDuringTransferAtBytes"] = stop.bytesAtStop
            }
            let jobURL = work.appendingPathComponent("job.json")
            try JSONEncoder().encode(job).write(to: jobURL, options: .atomic)
            let resumedProcess = Process(), output = Pipe()
            resumedProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            resumedProcess.arguments = ["--run-live", "--resume-fixture", jobURL.path]
            resumedProcess.standardOutput = output; resumedProcess.standardError = FileHandle.nullDevice
            try resumedProcess.run()
            let resumedOutput = output.fileHandleForReading.readDataToEndOfFile()
            resumedProcess.waitUntilExit()
            try check(resumedProcess.terminationStatus == 0 && String(decoding: resumedOutput, as: UTF8.self).contains("RESUMED-COMMITTED:2"), "Fresh-process resume did not commit both files")
            record["resumedInFreshProcess"] = true
            record["firstCommitted"] = 2
            let entries = try await client.tree(repo: target, recursive: true)
            try check(entries.contains { $0.path == "native-check/payload.bin" }, "Payload missing")
            try check(!entries.contains { $0.path.hasSuffix("excluded.txt") }, "Excluded file was uploaded")
            var hashes: [String: String] = [:]
            for name in ["notes.txt", "payload.bin"] {
                let url = URL(string: "https://huggingface.co/datasets/\(target.name)/resolve/main/native-check/\(name)")!
                var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (download, response) = try await session.download(for: request)
                defer { try? FileManager.default.removeItem(at: download) }
                let expected = try sha(source.appendingPathComponent(name))
                try check((response as? HTTPURLResponse)?.statusCode == 200 && (try sha(download)) == expected, "Downloaded bytes differ")
                hashes[name] = expected
            }
            record["downloadHashes"] = hashes
            let resumed = Events()
            try await NativeUploader.upload(job: job, token: token, checkpointDirectory: checkpoints, onEvent: { resumed.receive($0) })
            try check(resumed.progress.committed == 2 && resumed.progress.commits == 0, "Confirmed unchanged upload was not reused")
            record["resumeReusedConfirmedCommits"] = true
            _ = try await client.deleteFile(repo: target, path: "native-check/notes.txt")
            let repaired = Events()
            try await NativeUploader.upload(job: job, token: token, checkpointDirectory: checkpoints, onEvent: { repaired.receive($0) })
            try check(repaired.progress.commits > 0, "Changed remote head incorrectly reused receipts")
            let restored = try await client.tree(repo: target, path: "native-check")
            try check(restored.contains { $0.path == "native-check/notes.txt" }, "Resume did not restore deleted target")
            record["remoteChangeInvalidatedReceipts"] = true
            record["passed"] = true
        } catch {
            let message: String
            if let known = error as? NativeHubError { message = known.localizedDescription }
            else if let known = error as? NativeUploadError { message = known.localizedDescription }
            else if let known = error as? SmokeFailure { message = known.localizedDescription }
            else { message = "Native smoke operation failed (details suppressed)." }
            record["error"] = message.replacingOccurrences(of: token, with: "[redacted]")
        }
        if created, let repo {
            do {
                var request = URLRequest(url: URL(string: "https://huggingface.co/api/repos/delete")!)
                request.httpMethod = "DELETE"; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONSerialization.data(withJSONObject: ["name": String(repo.name.split(separator: "/").last!), "type": "dataset"])
                let (_, response) = try await session.data(for: request)
                try check((response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } == true, "Cleanup failed")
                do {
                    _ = try await client.info(repo: repo)
                    throw SmokeFailure(errorDescription: "Repository still exists after cleanup")
                } catch NativeHubError.http(let status, _) where status == 404 {
                    record["repoDeleted"] = true
                }
            } catch { record["cleanupError"] = "Failed to delete the recorded disposable repository." }
        }
        do { try FileManager.default.removeItem(at: work); record["fixtureRemoved"] = true }
        catch { record["fixtureRemoved"] = false }
        save()
        print(String(decoding: (try? JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])) ?? Data(), as: UTF8.self))
        if record["passed"] as? Bool != true || record["repoDeleted"] as? Bool != true { exit(1) }
    }
}
