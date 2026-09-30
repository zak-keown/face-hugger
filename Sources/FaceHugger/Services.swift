import AppKit
import Foundation
import Security

enum AppPaths {
    static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Face Hugger")
    #if STORE_BUILD
    static let isStoreEdition = true
    static var python: String {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        return Bundle.main.resourceURL!.appendingPathComponent("UploadRuntime.bundle/Contents/Resources/\(architecture)/python/bin/python3.12").path
    }
    #else
    static let isStoreEdition = false
    static let python = support.appendingPathComponent("runtime-v3/bin/python3").path
    #endif
    static let runtimeMarker = support.appendingPathComponent("runtime-ready-v3")
    static var runtimeReady: Bool {
        FileManager.default.isExecutableFile(atPath: python) && (isStoreEdition || FileManager.default.fileExists(atPath: runtimeMarker.path))
    }
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
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
            return
        }
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
    func run(executable: String, arguments: [String], token: String?, environmentOverrides: [String: String] = [:], onLine: @escaping @Sendable (String) -> Void) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async { [self] in
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                #if STORE_BUILD
                var env = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(),
                           "TMPDIR": NSTemporaryDirectory(), "HF_HOME": AppPaths.support.appendingPathComponent("huggingface").path,
                           "PYTHONDONTWRITEBYTECODE": "1", "PYTHONNOUSERSITE": "1"]
                #else
                var env = ProcessInfo.processInfo.environment
                #endif
                env.merge(environmentOverrides) { _, supplied in supplied }
                env["PYTHONUNBUFFERED"] = "1"; env["HF_HUB_DISABLE_TELEMETRY"] = "1"
                env["HF_HUB_DISABLE_UPDATE_CHECK"] = "1"
                if let token, !token.isEmpty { env["HF_TOKEN"] = token }
                process.environment = env
                process.standardOutput = pipe; process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do {
                    lock.lock()
                    if cancelled { lock.unlock(); continuation.resume(returning: 143); return }
                    do { try process.run() } catch { lock.unlock(); throw error }
                    lock.unlock()
                    var framer = JSONLineFramer(maxLineBytes: maxLineBytes)
                    var framingError: Error?
                    while true {
                        let data = pipe.fileHandleForReading.availableData
                        if data.isEmpty { break }
                        // Continue draining after cancellation so a child cannot block on a full pipe.
                        guard framingError == nil else { continue }
                        do {
                            for line in try framer.append(data) {
                                onLine(Self.redact(String(decoding: line, as: UTF8.self), token: token))
                            }
                        } catch {
                            framingError = error
                            stop()
                        }
                    }
                    if let line = framer.finish(), framingError == nil {
                        onLine(Self.redact(String(decoding: line, as: UTF8.self), token: token))
                    }
                    process.waitUntilExit()
                    if let framingError { continuation.resume(throwing: framingError) }
                    else { continuation.resume(returning: process.terminationStatus) }
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

final class HubResponseCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var response = HubResponseAccumulator()
    private var failure: Error?
    func append(_ line: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard failure == nil else { return false }
        do { try response.append(line); return true }
        catch { failure = error; return false }
    }
    func result(status: Int32) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw failure }
        return try response.result(exitStatus: status)
    }
}

enum HubService {
    static func request<T: Decodable & Sendable>(_ args: [String], token: String?, process: CommandProcess? = nil) async throws -> T {
        let collector = HubResponseCollector()
        let command = process ?? CommandProcess()
        let status = try await command.run(executable: AppPaths.python, arguments: [AppPaths.bridge] + args, token: token) { line in
            if !collector.append(line) { command.stop() }
        }
        return try JSONDecoder().decode(T.self, from: collector.result(status: status))
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
