import Foundation
import XCTest
@testable import FaceHuggerCore

final class FolderAccessTests: XCTestCase {
    func testStaleBookmarkMovesPathRefreshesAndBalancesScope() throws {
        let moved = URL(fileURLWithPath: "/moved/folder")
        var starts = 0, stops = 0, creations = 0
        let operations = FolderAccess.Operations(resolve: { _ in (moved, true) }, create: { url in
            XCTAssertEqual(url, moved); creations += 1; return Data([2])
        }, start: { _ in starts += 1; return true }, stop: { _ in stops += 1 })
        var access: FolderAccess? = try FolderAccess.restore(path: "/old/folder", bookmark: Data([1]), operations: operations)
        XCTAssertEqual(access?.url, moved)
        XCTAssertEqual(access?.bookmark, Data([2]))
        XCTAssertEqual(starts, 1); XCTAssertEqual(creations, 1); XCTAssertEqual(stops, 0)
        access?.close(); access?.close(); access = nil
        XCTAssertEqual(stops, 1)
    }

    func testIndependentOperationsRetainTheirOwnAccess() throws {
        var stops = 0
        let operations = FolderAccess.Operations(resolve: { _ in (URL(fileURLWithPath: "/source"), false) }, create: { _ in Data() }, start: { _ in true }, stop: { _ in stops += 1 })
        var workspace: FolderAccess? = try FolderAccess.restore(path: "/source", bookmark: nil, operations: operations)
        var upload: FolderAccess? = try FolderAccess.restore(path: "/source", bookmark: nil, operations: operations)
        XCTAssertNotNil(workspace); XCTAssertNotNil(upload)
        workspace = nil
        XCTAssertEqual(stops, 1, "Replacing the workspace must not close an upload's separate scope")
        upload = nil
        XCTAssertEqual(stops, 2)
    }

    func testFailedRefreshClosesAlreadyStartedScope() {
        var stops = 0
        let operations = FolderAccess.Operations(resolve: { _ in (URL(fileURLWithPath: "/source"), true) }, create: { _ in throw CocoaError(.fileWriteNoPermission) }, start: { _ in true }, stop: { _ in stops += 1 })
        XCTAssertThrowsError(try FolderAccess.restore(path: "/source", bookmark: Data([1]), operations: operations))
        XCTAssertEqual(stops, 1)
    }

    func testInvalidBookmarkNeverFallsBackToStoredPath() {
        var starts = 0
        let operations = FolderAccess.Operations(resolve: { _ in throw CocoaError(.fileReadCorruptFile) }, create: { _ in Data() }, start: { _ in starts += 1; return true }, stop: { _ in XCTFail("Scope was not started") })
        XCTAssertThrowsError(try FolderAccess.restore(path: "/possibly-replaced-folder", bookmark: Data([1]), operations: operations))
        XCTAssertEqual(starts, 0)
    }

    func testLegacyPathAndFalseStartDoNotStopUnownedScope() throws {
        let operations = FolderAccess.Operations(resolve: { _ in XCTFail("No bookmark to resolve"); return (URL(fileURLWithPath: "/"), false) }, create: { _ in XCTFail("Legacy paths are not user-selected grants"); return Data() }, start: { _ in false }, stop: { _ in XCTFail("Must not stop access that was not started") })
        let access = try FolderAccess.restore(path: "/legacy/folder", bookmark: nil, operations: operations)
        XCTAssertEqual(access.url.path, "/legacy/folder")
        XCTAssertNil(access.bookmark)
        access.close()
    }

    func testBookmarkFieldsRoundTripAndLegacyArchivesRemainReadable() throws {
        let repo = HubRepo(name: "owner/repo", kind: .model)
        let job = UploadJob(source: "/source", repo: repo, sourceBookmark: Data([1, 2, 3]))
        let pairing = SavedPairing(name: "Source", source: "/source", repo: repo, destination: "", includes: [], excludes: [], sourceBookmark: Data([4, 5, 6]))
        XCTAssertEqual(try JSONDecoder().decode(UploadJob.self, from: JSONEncoder().encode(job)).sourceBookmark, job.sourceBookmark)
        XCTAssertEqual(try JSONDecoder().decode(SavedPairing.self, from: JSONEncoder().encode(pairing)), pairing)
        for (data, isJob) in [(try JSONEncoder().encode(job), true), (try JSONEncoder().encode(pairing), false)] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object.removeValue(forKey: "sourceBookmark")
            let legacy = try JSONSerialization.data(withJSONObject: object)
            if isJob { XCTAssertNil(try JSONDecoder().decode(UploadJob.self, from: legacy).sourceBookmark) }
            else { XCTAssertNil(try JSONDecoder().decode(SavedPairing.self, from: legacy).sourceBookmark) }
        }
    }

    func testNativeBookmarkCapturesAndResolvesTemporaryFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let selected = try FolderAccess.selected(folder)
        defer { selected.close() }
        XCTAssertNotNil(selected.bookmark)
        let restored = try FolderAccess.restore(path: folder.path, bookmark: selected.bookmark)
        defer { restored.close() }
        XCTAssertEqual(restored.url.resolvingSymlinksInPath(), folder.resolvingSymlinksInPath())
    }
}
