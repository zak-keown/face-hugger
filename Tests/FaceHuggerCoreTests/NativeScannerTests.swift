import Foundation
import Testing
@testable import FaceHuggerCore

struct NativeScannerTests {
    @Test func pythonBracketAndUnicodeSemantics() {
        // Expected values cross-checked against Python fnmatchcase; HF normalizes
        // separators and appends '*' for a trailing slash before calling it.
        let cases: [(String, String, Bool)] = [
            ("b", "[^a]", false), ("^", "[^a]", true), ("a", "[^a]", true),
            ("a", "[[:alpha:]]", false), ("a]", "[[:alpha:]]", true),
            ("[", "[", true), ("[]", "[]", true), ("[!]", "[!]", true),
            ("]", "[]]", true), ("a", "[!]]", true), ("]", "[!]]", false),
            ("a", "[z-a]", false), ("a", "[!z-a]", true),
            ("-", "[a-b-c]", true), ("c", "[a-b-c]", true),
            ("a", "[a--b]", false), ("b", "[a--b]", true),
            ("é", "?", true), ("e\u{301}", "?", false),
            ("e\u{301}", "??", true), ("é", "e\u{301}", false),
            ("🙂", "?", true), ("ê", "[é-ë]", true),
            ("", "***", true), ("", "?", false), ("a/b", "*?*", true)
        ]
        for (path, pattern, expected) in cases {
            #expect(NativeScanner.matches(path, pattern: pattern) == expected, "path=\(path) pattern=\(pattern)")
        }
    }

    @Test func internalLinksAndDirectorySourceURL() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("café.txt")
        try Data("hello".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias.txt"), withDestinationURL: file)
        let result = try NativeScanner.scan(source: root)
        #expect(result.totalCount == 2)
        #expect(result.includedBytes == 10)
        #expect(result.files.map(\.path).contains("alias.txt"))
        #expect(result.files.allSatisfy { !$0.path.hasPrefix("/") && !$0.path.contains(root.lastPathComponent) })
    }

    @Test func brokenLinksFailEvenWithZeroPreviewRows() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("broken"), withDestinationURL: root.appendingPathComponent("missing"))
        #expect(throws: (any Error).self) { try NativeScanner.scan(source: root, limit: 0) }
    }

    @Test func callbackFailurePropagates() throws {
        enum CallbackFailure: Error { case stop }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("hello".utf8).write(to: root.appendingPathComponent("a.txt"))
        #expect(throws: CallbackFailure.self) {
            try NativeScanner.walk(source: root) { _ in throw CallbackFailure.stop }
        }
    }

    @Test func wildcardSemantics() {
        #expect(NativeScanner.matches("data/sub/file.json", pattern: "data/*.json"))
        #expect(NativeScanner.matches("data/sub/file.json", pattern: "data/"))
        #expect(NativeScanner.matches("data/sub/file.json", pattern: "data\\*.json"))
        #expect(NativeScanner.matches("a.json", pattern: "[!b]*.json"))
        #expect(!NativeScanner.matches("A.JSON", pattern: "*.json"))
        #expect(NativeScanner.matches(".hidden", pattern: "*"))
    }
    @Test func cappedPreviewStillCountsAndIgnoresInternals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["a.json", "nested/b.json", "c.txt", ".git/config", "nested/.cache/huggingface/state"] {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("hello".utf8).write(to: url)
        }
        let result = try NativeScanner.scan(source: root, includes: ["*.json"], limit: 1)
        #expect(result.files.count == 1)
        #expect(result.totalCount == 3)
        #expect(result.includedCount == 2)
        #expect(result.includedBytes == 10)
        #expect(result.truncated)
    }
    @Test func rejectsExternalFileLinksAndSkipsDirectoryLinks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        #expect(throws: NativeScanError.self) { try NativeScanner.scan(source: root) }
        try FileManager.default.removeItem(at: root.appendingPathComponent("linked"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("directory"), withDestinationURL: root.deletingLastPathComponent())
        #expect(try NativeScanner.scan(source: root).totalCount == 0)
    }
}
