import XCTest
@testable import FaceHuggerCore

final class QueueTests: XCTestCase {
    private func job() -> UploadJob {
        UploadJob(source: "/tmp", repo: HubRepo(name: "owner/repo", kind: .model))
    }

    func testStopRemainsCancellationWhenQueueRestartedBeforeExit() {
        let first = job(), second = job()
        var control = UploadQueueControl()
        control.start()
        XCTAssertEqual(control.beginNext(in: [first, second]), first.id)
        control.stop()
        control.start(preferredJobID: second.id)
        XCTAssertNil(control.beginNext(in: [first, second]), "A stopping process still owns the active slot")
        XCTAssertEqual(control.finish(first.id, exitStatus: 15), .stopped)
        XCTAssertTrue(control.isRunning)
        XCTAssertEqual(control.beginNext(in: [first, second]), second.id)
    }

    func testExplicitStartPrioritizesSelectedQueuedJob() {
        let first = job(), selected = job()
        var control = UploadQueueControl()
        control.start(preferredJobID: selected.id)
        XCTAssertEqual(control.beginNext(in: [first, selected]), selected.id)
        XCTAssertEqual(control.finish(selected.id, exitStatus: 0), .completed)
        XCTAssertEqual(control.beginNext(in: [first]), first.id)
    }

    func testRemovedPreferredJobFallsBackToQueueOrder() {
        let first = job(), removed = job()
        var control = UploadQueueControl()
        control.start(preferredJobID: removed.id)
        XCTAssertEqual(control.beginNext(in: [first]), first.id)
    }

    func testFailurePausesRemainingQueueAndCanBeResumed() {
        let first = job(), second = job()
        var control = UploadQueueControl()
        control.start()
        _ = control.beginNext(in: [first, second])
        XCTAssertEqual(control.finish(first.id, exitStatus: 1), .failed)
        XCTAssertFalse(control.isRunning)
        XCTAssertNil(control.beginNext(in: [second]))
        control.start()
        XCTAssertEqual(control.beginNext(in: [second]), second.id)
    }

    func testStoppedQueueDoesNotAdvanceWithoutStart() {
        let first = job(), second = job()
        var control = UploadQueueControl()
        control.start()
        _ = control.beginNext(in: [first])
        control.stop()
        XCTAssertEqual(control.finish(first.id, exitStatus: -1), .stopped)
        XCTAssertNil(control.beginNext(in: [second]))
    }

    func testSuccessfulExitWinsOverLateStopRequest() {
        let first = job()
        var control = UploadQueueControl()
        control.start()
        _ = control.beginNext(in: [first])
        control.stop()
        XCTAssertEqual(control.finish(first.id, exitStatus: 0), .completed)
        XCTAssertFalse(control.isRunning)
    }

    func testStaleCompletionCannotReleaseAnotherJobsActiveSlot() {
        let first = job(), second = job()
        var control = UploadQueueControl()
        control.start()
        _ = control.beginNext(in: [first])
        _ = control.finish(first.id, exitStatus: 0)
        _ = control.beginNext(in: [second])
        XCTAssertNil(control.finish(first.id, exitStatus: 1))
        XCTAssertEqual(control.activeJobID, second.id)
        XCTAssertTrue(control.isRunning)
    }

    func testDrainedQueueDoesNotStartNewlyAddedJobAutomatically() {
        let first = job(), addedLater = job()
        var control = UploadQueueControl()
        control.start()
        _ = control.beginNext(in: [first])
        _ = control.finish(first.id, exitStatus: 0)
        XCTAssertNil(control.beginNext(in: []))
        XCTAssertFalse(control.isRunning)
        XCTAssertNil(control.beginNext(in: [addedLater]))
    }

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
        var control = UploadQueueControl()
        XCTAssertNil(control.beginNext(in: loaded))
        control.start()
        XCTAssertNil(control.beginNext(in: loaded), "Interrupted uploads require explicit resume")
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
