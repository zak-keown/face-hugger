import Foundation
import XCTest
@testable import FaceHuggerCore

final class BridgeProtocolTests: XCTestCase {
    func testFragmentedUTF8AndMultipleFramesRemainIntact() throws {
        let text = "{\"path\":\"folder/ü 🐙.bin\"}\n{\"count\":2}\n"
        var framer = JSONLineFramer(maxLineBytes: 128_000)
        var lines: [Data] = []
        for byte in text.utf8 { lines += try framer.append(Data([byte])) }
        XCTAssertEqual(lines.map { String(decoding: $0, as: UTF8.self) }, ["{\"path\":\"folder/ü 🐙.bin\"}", "{\"count\":2}"])
        XCTAssertNil(framer.finish())
    }
    func testOversizedFrameThrowsInsteadOfEmittingFragments() throws {
        var framer = JSONLineFramer(maxLineBytes: 8)
        XCTAssertTrue(try framer.append(Data("12345678".utf8)).isEmpty)
        XCTAssertThrowsError(try framer.append(Data("9\n".utf8)))
        var complete = JSONLineFramer(maxLineBytes: 8)
        XCTAssertThrowsError(try complete.append(Data("123456789\n".utf8)))
    }
    func testLargeDirectoryStreamsBeyondOld128KLimit() throws {
        var response = HubResponseAccumulator()
        var framer = JSONLineFramer(maxLineBytes: 128_000)
        var stream = Data()
        for index in 0..<4000 {
            stream.append(Data("{\"event\":\"item\",\"data\":{\"path\":\"folder/ü long filename \(index).bin\",\"type\":\"file\",\"size\":42}}\n".utf8))
        }
        stream.append(Data("{\"event\":\"result\",\"streamed\":true,\"count\":4000}\n".utf8))
        XCTAssertGreaterThan(stream.count, 128_000)
        for offset in stride(from: 0, to: stream.count, by: 4093) {
            for frame in try framer.append(stream.subdata(in: offset..<min(offset + 4093, stream.count))) {
                try response.append(String(decoding: frame, as: UTF8.self))
            }
        }
        let rows = try JSONSerialization.jsonObject(with: response.result(exitStatus: 0)) as! [[String: Any]]
        XCTAssertEqual(rows.count, 4000)
        XCTAssertEqual(rows.last?["path"] as? String, "folder/ü long filename 3999.bin")
    }
    func testPartialFailureAndCountMismatchCannotBecomeSuccessfulListing() throws {
        var response = HubResponseAccumulator()
        try response.append("{\"event\":\"item\",\"data\":{\"path\":\"first\"}}")
        XCTAssertThrowsError(try response.result(exitStatus: 0))
        XCTAssertThrowsError(try response.append("{\"event\":\"result\",\"streamed\":true,\"count\":2}"))
        try response.append("{\"event\":\"error\",\"message\":\"Connection timed out\"}")
        XCTAssertThrowsError(try response.result(exitStatus: 1)) { error in
            XCTAssertEqual(error.localizedDescription, "Connection timed out")
        }
    }
    func testListingBoundsAndExitStatusAreEnforced() throws {
        var response = HubResponseAccumulator(maxItems: 1, maxBytes: 100)
        try response.append("{\"event\":\"item\",\"data\":1}")
        XCTAssertThrowsError(try response.append("{\"event\":\"item\",\"data\":2}"))
        var bytes = HubResponseAccumulator(maxItems: 10, maxBytes: 2)
        XCTAssertThrowsError(try bytes.append("{\"event\":\"item\",\"data\":\"large\"}"))
        var finished = HubResponseAccumulator()
        try finished.append("{\"event\":\"result\",\"streamed\":true,\"count\":0}")
        XCTAssertThrowsError(try finished.result(exitStatus: 1))
        XCTAssertThrowsError(try finished.append("{\"event\":\"item\",\"data\":1}"))
    }
    func testLegacyResultAndOrdinaryStderrStillWork() throws {
        var response = HubResponseAccumulator()
        try response.append("an ordinary SDK warning")
        try response.append("{\"event\":\"result\",\"data\":{\"name\":\"alice\"}}")
        let result = try JSONSerialization.jsonObject(with: response.result(exitStatus: 0)) as! [String: String]
        XCTAssertEqual(result, ["name": "alice"])
    }
}
