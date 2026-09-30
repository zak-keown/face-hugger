import Foundation
import CryptoKit

/// Bootstrap stays in the app's support directory and never edits shell profiles.
enum RuntimeBootstrap {
    static let version = "0.12.18"
    static let systemCandidates = ["/opt/homebrew/bin/uv", "/usr/local/bin/uv", NSHomeDirectory() + "/.local/bin/uv"]

    static func prepare(in support: URL, candidates: [String] = systemCandidates) async throws -> String {
        if let installed = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return installed }
        #if arch(arm64)
        let platform = "aarch64-apple-darwin"
        let checksum = "cf40e0c6a202190ccd9e0406dcfdd5b2d6668a9a5c779b17948963df32aafe5b"
        #else
        let platform = "x86_64-apple-darwin"
        let checksum = "2e4108f5395397c8bc5d43bf83d3bdbb2d0e92b90d0efa607756be704905fa33"
        #endif
        let tools = support.appendingPathComponent("tools/uv-\(version)-\(platform)")
        let executable = tools.appendingPathComponent("uv")
        if FileManager.default.isExecutableFile(atPath: executable.path) { return executable.path }
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("face-hugger-bootstrap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let url = URL(string: "https://github.com/astral-sh/uv/releases/download/\(version)/uv-\(platform).tar.gz")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        let (download, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: download) }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw failure("Could not download setup tools. Check your connection and try again.")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: download, options: .mappedIfSafe)).map { String(format: "%02x", $0) }.joined()
        guard digest == checksum else { throw failure("Setup download failed its integrity check. Please try again.") }
        let archive = temporary.appendingPathComponent("uv.tar.gz")
        try FileManager.default.moveItem(at: download, to: archive)
        let status = try await CommandProcess().run(executable: "/usr/bin/tar", arguments: ["-xzf", archive.path, "-C", temporary.path, "uv-\(platform)/uv"], token: nil) { _ in }
        let extracted = temporary.appendingPathComponent("uv-\(platform)/uv")
        guard status == 0, FileManager.default.isExecutableFile(atPath: extracted.path) else { throw failure("Could not unpack setup tools. Please try again.") }
        // Copy only the verified executable; never execute a downloaded shell installer.
        if FileManager.default.fileExists(atPath: executable.path) { try FileManager.default.removeItem(at: executable) }
        try FileManager.default.moveItem(at: extracted, to: executable)
        return executable.path
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "FaceHugger.Setup", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
