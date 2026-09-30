import Foundation
import Testing
@testable import FaceHuggerCore

struct DatasetCardTests {
    private func fixture(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return root
    }

    @Test func totalsUseEntireFilteredInventoryAndPathsUseDestination() throws {
        let root = try fixture(["z.csv": "123", "a.csv": "12", "nested/b.csv": "1234", "private.txt": "secret", ".git/config": "ignored"])
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = try DatasetCardFacts.collect(source: root, includes: ["*.csv"], uploadPath: "/train/", sampleLimit: 1)
        #expect(facts.includedCount == 3)
        #expect(facts.includedBytes == 9)
        #expect(facts.excludedCount == 1)
        #expect(facts.samplePaths == ["train/a.csv"])
        #expect(facts.pathsTruncated)
        #expect(facts.formats == [DatasetCardFormat(fileExtension: "csv", count: 3, bytes: 9)])
        let card = DatasetCard.render(facts: facts, input: .init())
        #expect(card.contains("Included files: 3"))
        #expect(card.contains("partial list"))
        #expect(!card.contains("secret"))
    }

    @Test func noLicenseProvenanceOrRecordCountIsInvented() throws {
        let root = try fixture(["MIT-license.txt": "MIT", "data.json": "[{\"secret\":42}]"])
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = try DatasetCardFacts.collect(source: root)
        let card = DatasetCard.render(facts: facts, input: .init(title: "Useful dataset"))
        #expect(card.hasPrefix("# Useful dataset\n"))
        #expect(card.contains("No license has been inferred"))
        #expect(card.contains("TODO: Document the source"))
        #expect(card.contains("File counts are not record counts"))
        #expect(!card.contains("license: mit"))
        #expect(!facts.modelSummary.contains("secret"))
        #expect(facts.modelSummary.contains("\"contentsInspected\":false"))
    }

    @Test func suffixMemoryAndExamplePathsAreBounded() throws {
        var files: [String: String] = ["no-extension": "abc"]
        for index in 0..<100 { files["file\(index).unique\(index)"] = "x" }
        let root = try fixture(files)
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = try DatasetCardFacts.collect(source: root, sampleLimit: 10000)
        #expect(facts.includedCount == 101)
        #expect(facts.includedBytes == 103)
        #expect(facts.samplePaths.count == 50)
        #expect(facts.formats.count == 2)
        #expect(facts.otherFormatCount == 100)
        let summary = try #require(JSONSerialization.jsonObject(with: Data(facts.modelSummary.utf8)) as? [String: Any])
        #expect((summary["examplePaths"] as? [String])?.count == 12)
    }

    @Test func metadataCannotInjectMarkupAndUserSuppliedSectionsArePreserved() throws {
        let root = try fixture(["<img src=x>.json": "not actually json"])
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = try DatasetCardFacts.collect(source: root)
        let card = DatasetCard.render(facts: facts, input: .init(title: "Title\n# Inject", purpose: "Classify samples.", provenance: "Collected by me.", license: "CC-BY-4.0", limitations: "English only."))
        #expect(card.contains("&lt;img src=x&gt;.json"))
        #expect(!card.contains("<img"))
        #expect(!card.contains("\n# Inject"))
        #expect(card.contains("Classify samples."))
        #expect(card.contains("Collected by me."))
        #expect(card.contains("CC-BY-4.0"))
        #expect(card.contains("English only."))
        #expect(card.contains("contents have not been inspected"))
    }

    @Test func excludedOnlySelectionHasNoExamplesOrClaimedFormats() throws {
        let root = try fixture(["secret.csv": "abc"])
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = try DatasetCardFacts.collect(source: root, excludes: ["*"])
        #expect(facts.includedCount == 0)
        #expect(facts.includedBytes == 0)
        #expect(facts.excludedCount == 1)
        #expect(facts.formats.isEmpty)
        #expect(facts.samplePaths.isEmpty)
        #expect(!facts.pathsTruncated)
        #expect(!DatasetCard.render(facts: facts, input: .init()).contains("secret.csv"))
    }
}
