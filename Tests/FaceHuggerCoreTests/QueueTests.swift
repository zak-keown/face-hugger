import XCTest
@testable import FaceHuggerCore

final class QueueTests: XCTestCase {
    func testInterruptedJobIsRecoveredWithoutRestarting() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = QueueArchive(url: dir.appendingPathComponent("queue.json"))
        var job = UploadJob(source: "/tmp", repo: HubRepo(name: "owner/repo", kind: .model))
        job.state = .running
        try archive.save([job])
        let loaded = try archive.load()
        XCTAssertEqual(loaded.first?.state, .interrupted)
        XCTAssertEqual(loaded.first?.id, job.id)
    }
    func testDestinationCannotEscapeRepo() {
        for destination in ["../secret", "/absolute", "a/../../b", "a\\b", ".", "a/./b", "folder\rname"] {
            XCTAssertNotNil(UploadValidation.error(source: NSTemporaryDirectory(), repo: "owner/repo", destination: destination))
        }
        XCTAssertNil(UploadValidation.error(source: NSTemporaryDirectory(), repo: "owner/repo", destination: "checkpoints/epoch-10"))
    }
    func testRepoAndSourceValidation() {
        XCTAssertNotNil(UploadValidation.error(source: NSTemporaryDirectory(), repo: "bad", destination: ""))
        XCTAssertNotNil(UploadValidation.error(source: "/missing-\(UUID())", repo: "owner/repo", destination: ""))
    }
}
