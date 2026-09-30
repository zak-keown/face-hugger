import Foundation
import CryptoKit

struct ProbeFailure: Error { let message: String }
func fail(_ message: String) -> ProbeFailure { ProbeFailure(message: message) }
func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) }
func object(_ data: Data) throws -> [String: Any] { guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw fail("Invalid JSON object") }; return value }
func digest(_ url: URL) throws -> String {
    let f = try FileHandle(forReadingFrom: url); defer { try? f.close() }
    var h = SHA256()
    while let bytes = try f.read(upToCount: 1024 * 1024), !bytes.isEmpty { h.update(data: bytes) }
    return h.finalize().map { String(format: "%02x", $0) }.joined()
}
// Never forward the Hub bearer token to storage hosts or downgrade redirects.
final class Network: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard request.url?.scheme == "https" else { completionHandler(nil); return }
        var next = request
        if request.url?.host != "huggingface.co" { next.setValue(nil, forHTTPHeaderField: "Authorization") }
        completionHandler(next)
    }
    func request(_ url: String, method: String = "GET", token: String? = nil, body: Data? = nil, file: URL? = nil, type: String = "application/json") async throws -> (Data, HTTPURLResponse) {
        guard let target = URL(string: url), target.scheme == "https" else { throw fail("HTTPS required") }
        var r = URLRequest(url: target); r.httpMethod = method; r.timeoutInterval = 90
        r.setValue(type, forHTTPHeaderField: "Content-Type")
        if let token { guard target.host == "huggingface.co" else { throw fail("Refusing token outside Hub") }; r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let result: (Data, URLResponse)
        if let file { result = try await session.upload(for: r, fromFile: file) }
        else { r.httpBody = body; result = try await session.data(for: r) }
        guard let response = result.1 as? HTTPURLResponse else { throw fail("No HTTP response") }
        guard (200..<300).contains(response.statusCode) else { throw fail("HTTP \(response.statusCode) for \(method) \(target.host ?? "host")") }
        return (result.0, response)
    }
}
@main struct Probe {
    static func main() async {
        guard CommandLine.arguments.contains("--run-live"), let token = ProcessInfo.processInfo.environment["HF_TOKEN"], !token.isEmpty else { print("Use --run-live with HF_TOKEN in environment. Credentials are never logged."); return }
        let fm = FileManager.default; let work = URL(fileURLWithPath: ".build/native-transport/run-" + UUID().uuidString)
        var record: [String: Any] = ["transport": "Apple URLSession", "hashing": "Apple CryptoKit", "passed": false, "repoDeleted": false, "scope": "Bounded native LFS proof, not production uploader or Xet parity"]
        let report = URL(fileURLWithPath: ".build/native-transport/result.json")
        func save() { if let d = try? json(record) { try? d.write(to: report, options: .atomic) } }
        let net = Network(); var repo: String?; var created = false
        do {
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let me = try object(try await net.request("https://huggingface.co/api/whoami-v2", token: token).0)
            guard let owner = me["name"] as? String else { throw fail("No owner") }
            let name = "face-hugger-native-" + UUID().uuidString.lowercased().prefix(12)
            repo = owner + "/" + name; record["repo"] = repo; save()
            _ = try await net.request("https://huggingface.co/api/repos/create", method: "POST", token: token, body: json(["name":name,"type":"dataset","private":true]))
            created = true; save()
            let info = try object(try await net.request("https://huggingface.co/api/datasets/\(repo!)", token: token).0)
            guard info["private"] as? Bool == true else { throw fail("Private repo verification failed") }
            let payload = work.appendingPathComponent("payload.bin")
            fm.createFile(atPath: payload.path, contents: nil)
            let f = try FileHandle(forWritingTo: payload)
            // Unique, bounded fixture; no existing user files are read.
            var generator = SystemRandomNumberGenerator()
            for _ in 0..<16 { var block = Data(count: 1024 * 1024); block.withUnsafeMutableBytes { raw in
                let words = raw.bindMemory(to: UInt64.self); for i in words.indices { words[i] = generator.next() }
            }; try f.write(contentsOf: block) }
            try f.close()
            let size = 16 * 1024 * 1024; let oid = try digest(payload)
            record["bytes"] = size; record["sha256"] = oid
            let base = "https://huggingface.co/datasets/\(repo!).git/info/lfs/objects/batch"
            let batchBody: [String: Any] = ["operation":"upload","transfers":["basic","multipart"],"objects":[["oid":oid,"size":size]],"hash_algo":"sha256","ref":["name":"main"]]
            let batch = try object(try await net.request(base, method:"POST",token:token,body:json(batchBody),type:"application/vnd.git-lfs+json").0)
            guard let objects = batch["objects"] as? [[String: Any]], let first = objects.first, first["error"] == nil else { throw fail("LFS batch rejected object") }
            var partCount = 0
            if let actions = first["actions"] as? [String: Any], let upload = actions["upload"] as? [String: Any], let href = upload["href"] as? String {
                let headers = upload["header"] as? [String: Any] ?? [:]
                if let chunkText = headers["chunk_size"] as? String, let chunk = Int(chunkText), chunk > 0 {
                    let urls = headers.compactMap { key,value -> (Int,String)? in guard let n = Int(key), let url = value as? String else { return nil }; return (n,url) }.sorted { $0.0 < $1.0 }
                    guard urls.count == (size + chunk - 1) / chunk else { throw fail("Invalid multipart count") }
                    let source = try FileHandle(forReadingFrom: payload); defer { try? source.close() }
                    var parts: [[String: Any]] = []
                    for (number,url) in urls {
                        let part = work.appendingPathComponent("part.bin"); fm.createFile(atPath:part.path,contents:nil)
                        let out = try FileHandle(forWritingTo:part); var remaining = min(chunk, size - (number - 1) * chunk)
                        while remaining > 0 { guard let data = try source.read(upToCount:min(remaining,1024*1024)), !data.isEmpty else { throw fail("Short source") }; try out.write(contentsOf:data); remaining -= data.count }
                        try out.close()
                        let response = try await net.request(url,method:"PUT",file:part,type:"application/octet-stream").1
                        guard let etag = response.value(forHTTPHeaderField:"ETag") else { throw fail("No part ETag") }
                        parts.append(["partNumber":number,"etag":etag]);partCount += 1
                        try fm.removeItem(at:part)
                    }
                    _ = try await net.request(href,method:"POST",body:json(["oid":oid,"parts":parts]),type:"application/vnd.git-lfs+json")
                    record["uploadMode"] = "multipart"
                } else {
                    _ = try await net.request(href,method:"PUT",file:payload,type:"application/octet-stream");partCount = 1;record["uploadMode"] = "basic"
                }
                if let verify = actions["verify"] as? [String: Any], let href = verify["href"] as? String {
                    _ = try await net.request(href,method:"POST",token:token,body:json(["oid":oid,"size":size]))
                }
            } else { throw fail("Unique payload unexpectedly already present") }
            record["partsUploaded"] = partCount;save()
            let text = Data("Native Apple-networking proof. Disposable test repository.\n".utf8)
            let lines: [[String:Any]] = [["key":"header","value":["summary":"Native URLSession upload proof"]],["key":"file","value":["path":"README.md","encoding":"base64","content":text.base64EncodedString()]],["key":"lfsFile","value":["path":"payload.bin","algo":"sha256","oid":oid,"size":size]]]
            var ndjson = Data();for line in lines {ndjson.append(try json(line));ndjson.append(10)}
            _ = try await net.request("https://huggingface.co/api/datasets/\(repo!)/commit/main",method:"POST",token:token,body:ndjson,type:"application/x-ndjson")
            record["committed"] = true;save()
            // URLSession downloads to a file, keeping the payload out of application memory.
            var downloadRequest = URLRequest(url:URL(string:"https://huggingface.co/datasets/\(repo!)/resolve/main/payload.bin")!)
            downloadRequest.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
            let (download,response) = try await net.session.download(for:downloadRequest)
            defer { try? fm.removeItem(at:download) }
            guard (response as? HTTPURLResponse)?.statusCode == 200, try digest(download) == oid else {throw fail("Download hash mismatch")}
            record["downloadVerified"] = true
            let repeated = try object(try await net.request(base,method:"POST",token:token,body:json(batchBody),type:"application/vnd.git-lfs+json").0)
            guard let repeatedObjects = repeated["objects"] as? [[String:Any]], repeatedObjects.count == 1,
                  let completed = repeatedObjects.first, completed["oid"] as? String == oid,
                  completed["error"] == nil, completed["actions"] == nil else { throw fail("Completed-object deduplication not confirmed") }
            record["repeatUploadSkipped"] = true
            record["passed"] = true
        } catch { record["error"] = (error as? ProbeFailure)?.message ?? "Native request or filesystem operation failed (details suppressed to protect URLs and credentials)" }
        if created, let repo {
            do { _ = try await net.request("https://huggingface.co/api/repos/delete",method:"DELETE",token:token,body:json(["name":String(repo.split(separator:"/").last!),"type":"dataset"]));record["repoDeleted"] = true }
            catch { record["cleanupError"] = "Repository deletion failed; use recorded repo ID to clean up" }
        }
        if fm.fileExists(atPath:work.path) { do { try fm.removeItem(at:work);record["fixtureRemoved"] = true } catch { record["fixtureRemoved"] = false } }
        save();print(String(data:try! json(record),encoding:.utf8)!)
        if record["passed"] as? Bool != true || record["repoDeleted"] as? Bool != true { exit(1) }
    }
}
