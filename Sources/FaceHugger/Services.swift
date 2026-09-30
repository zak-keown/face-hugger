import AppKit
import Foundation
import Security

enum AppPaths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Face Hugger")
    static let python = support.appendingPathComponent("runtime/bin/python3").path
    static let runtimeMarker = support.appendingPathComponent("runtime-ready-v2")
    static var bridge: String { Bundle.main.url(forResource: "bridge", withExtension: "py")!.path }
}

enum CredentialStore {
    static let service = "dev.zakkeown.FaceHugger"
    static func read() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "huggingface", kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "huggingface"]
        if token.isEmpty { SecItemDelete(query as CFDictionary); return }
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: Data(token.utf8)] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(updated)) }
        var item = query; item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}

final class CommandProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var cancelled = false
    private let maxLineBytes: Int
    init(maxLineBytes: Int = 128_000) { self.maxLineBytes = maxLineBytes }
    func stop() {
        lock.lock(); cancelled = true
        if process.isRunning { process.terminate() }
        lock.unlock()
    }
    func run(executable: String, arguments: [String], token: String?, onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                var env = ProcessInfo.processInfo.environment
                env["PYTHONUNBUFFERED"] = "1"; env["HF_HUB_DISABLE_TELEMETRY"] = "1"
                if let token, !token.isEmpty { env["HF_TOKEN"] = token }
                process.environment = env
                process.standardOutput = pipe; process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do {
                    lock.lock()
                    if cancelled { lock.unlock(); continuation.resume(returning: 143); return }
                    do { try process.run() } catch { lock.unlock(); throw error }
                    lock.unlock()
                    var buffer = Data()
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        buffer.append(data)
                        while let index = buffer.firstIndex(of: 10) {
                            let line = String(decoding: buffer[..<index], as: UTF8.self)
                            buffer.removeSubrange(...index)
                            onLine(Self.redact(line, token: token))
                        }
                        if buffer.count > maxLineBytes { onLine(Self.redact(String(decoding: buffer, as: UTF8.self), token: token)); buffer.removeAll() }
                    }
                    if !buffer.isEmpty { onLine(Self.redact(String(decoding: buffer, as: UTF8.self), token: token)) }
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func redact(_ value: String, token: String?) -> String {
        var result = value
        if let token, !token.isEmpty { result = result.replacingOccurrences(of: token, with: "[redacted]") }
        return result.replacingOccurrences(of: "hf_[A-Za-z0-9]+", with: "[redacted]", options: .regularExpression)
    }
}

struct HubIdentity: Decodable, Sendable {
    var name: String
    var organizations: [String]
}
struct RepoResponse: Decodable, Sendable {
    var id: String
    var type: String
    var `private`: Bool
    var repo: HubRepo { HubRepo(name: id, kind: RepoKind(rawValue: type) ?? .model, isPrivate: self.private) }
}
struct RemoteEntry: Decodable, Identifiable, Hashable, Sendable {
    var id: String { path }
    var path: String
    var type: String
    var size: Int64?
    var isDirectory: Bool { type == "directory" }
    var name: String { path.split(separator: "/").last.map(String.init) ?? path }
}

actor CommandOutput {
    var lines: [String] = []
    func append(_ line: String) { lines.append(line) }
    func result() -> [String] { lines }
}

enum HubService {
    static func request<T: Decodable & Sendable>(_ args: [String], token: String?, process: CommandProcess? = nil) async throws -> T {
        let output = CommandOutput()
        // Serialize line collection on a dedicated queue so the final result cannot overtake output.
        let collector = LineCollector()
        let status = try await (process ?? CommandProcess()).run(executable: AppPaths.python, arguments: [AppPaths.bridge] + args, token: token) { collector.append($0) }
        for line in collector.lines() { await output.append(line) }
        var failure: String?
        for line in await output.result() {
            guard let data = line.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if object["event"] as? String == "error" { failure = object["message"] as? String }
            if status == 0, object["event"] as? String == "result", let result = object["data"] {
                return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: result))
            }
        }
        throw NSError(domain: "FaceHugger", code: Int(status), userInfo: [NSLocalizedDescriptionKey: failure ?? "Hugging Face did not return a result. Check your connection and upload tools."])
    }
}

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var limit: Int?
    init(limit: Int? = nil) { self.limit = limit }
    func append(_ line: String) { lock.lock(); storage.append(line); if let limit, storage.count > limit { storage.removeFirst(storage.count - limit) }; lock.unlock() }
    func lines() -> [String] { lock.lock(); defer { lock.unlock() }; return storage }
}
