import Testing
@testable import FaceHuggerCore
struct NativeComparisonTests {
    @Test func unicodePathsUseByteIdentity() {
        let composed = "caf\u{e9}.txt", decomposed = "cafe\u{301}.txt"
        var index = NativePathComparison(paths: [composed, decomposed], destination: "")
        index.observe(path: composed, isDirectory: false)
        let result = index.result(complete: true)
        #expect(result.paths.count == 1)
        #expect(Array(result.paths[0].utf8) == Array(composed.utf8))
    }
    @Test func ancestorsAndFolderCollisions() {
        var index = NativePathComparison(paths: ["notes.txt", "nested/a.bin", "folder"], destination: "uploads")
        index.observe(path: "uploads/notes.txt", isDirectory: false)
        index.observe(path: "uploads/nested", isDirectory: false)
        index.observe(path: "uploads/folder", isDirectory: true)
        let result = index.result(complete: true)
        #expect(result.paths == ["folder", "notes.txt"])
        #expect(result.conflicts.map(\.path) == ["folder", "nested/a.bin"])
    }
    @Test func missingPathsAreNotProvenByPartialListing() {
        var index = NativePathComparison(paths: ["a", "a_b/file", "different"], destination: "")
        index.observe(path: "a", isDirectory: false)
        let result = index.result(complete: false)
        #expect(!result.complete)
        #expect(result.paths == ["a"])
        #expect(result.conflicts.isEmpty)
    }
}

import Foundation
extension NativeComparisonTests {
    @Test func diskIndexHandlesLiteralWildcardsAndUnicode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let index = try NativeUploadPathIndex(url: url, destination: "target")
        try index.add(path: "a_%/é.bin")
        try index.add(path: "aX/other")
        try index.add(path: "folder")
        #expect(try index.observe(path: "target/a_%", isDirectory: false)?.path == "a_%/é.bin")
        #expect(try index.observe(path: "target/a_", isDirectory: false) == nil)
        #expect(try index.observe(path: "target/folder", isDirectory: true)?.path == "folder")
        #expect(try index.observe(path: "target/folder", isDirectory: false) == nil)
        try index.close()
    }
}
