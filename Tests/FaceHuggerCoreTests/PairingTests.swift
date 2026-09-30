import Foundation
import XCTest
@testable import FaceHuggerCore

final class PairingTests: XCTestCase {
    func testRoundTripPreservesUnicodeRoutesFiltersAndVisibility() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = PairingArchive(url: directory.appendingPathComponent("nested/pairings.json"))
        let pairings = [
            SavedPairing(
                name: "Évaluation · 日本語 🫂",
                source: "/Users/example/Model runs/評価 v2",
                repo: HubRepo(name: "owner/private-data", kind: .dataset, isPrivate: true),
                destination: "results/評価 final",
                includes: ["**/*.json", "weights/*.safetensors"],
                excludes: [".DS_Store", "**/.DS_Store", "**/logs/**"]
            ),
            SavedPairing(
                name: "Public model root",
                source: "/tmp/checkpoint",
                repo: HubRepo(name: "owner/public-model", kind: .model, isPrivate: false),
                destination: "",
                includes: [],
                excludes: []
            )
        ]
        try archive.save(pairings)
        XCTAssertEqual(try archive.load(), pairings)
        // Loading a route preserves its identity instead of minting a new preset.
        XCTAssertEqual(try archive.load().map(\.id), pairings.map(\.id))
        // Removing presets and saving must replace the archive, not append to it.
        try archive.save([pairings[1]])
        XCTAssertEqual(try archive.load(), [pairings[1]])
    }

    func testMissingArchiveLoadsEmptyWithoutCreatingFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pairings.json")
        XCTAssertEqual(try PairingArchive(url: url).load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMalformedArchiveThrowsInsteadOfSilentlyLosingPresets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("pairings.json")
        for contents in ["{broken JSON", "{}", "[{\"name\":\"missing required route fields\"}]"] {
            let bytes = Data(contents.utf8)
            try bytes.write(to: url)
            XCTAssertThrowsError(try PairingArchive(url: url).load()) { error in
                XCTAssertTrue(error is DecodingError)
            }
            XCTAssertEqual(try Data(contentsOf: url), bytes, "A failed read must preserve the original archive for recovery")
        }
    }
}
