import XCTest
@testable import FaceHuggerCore

final class RecoveryTests: XCTestCase {
    func testUnavailableSourceTakesPriorityOverPersistedError() {
        XCTAssertEqual(UploadRecoveryHint.classify(message: "401 Client Error", sourceExists: false), .missingSource)
        XCTAssertEqual(UploadRecoveryHint.classify(message: "", sourceExists: false), .missingSource)
    }

    func testAccountHintsRecognizeExplicitAuthorizationFailures() {
        for message in ["401 Client Error: Unauthorized", "403 Client Error: Forbidden", "HTTP 403", "Status code: 401", "Invalid token", "Authentication failed", "Token has expired", "You need write access to this repository"] {
            XCTAssertEqual(UploadRecoveryHint.classify(message: message, sourceExists: true), .authentication, message)
        }
    }

    func testNetworkHintsRecognizeTransportFailures() {
        for message in ["httpx.ConnectError: connection refused", "ReadTimeout", "Connection reset by peer", "Temporary failure in name resolution", "Network is unreachable", "Read timed out"] {
            XCTAssertEqual(UploadRecoveryHint.classify(message: message, sourceExists: true), .network, message)
        }
    }

    func testAmbiguousErrorsDoNotInventDiagnosis() {
        for message in ["", "Upload failed", "Repository not found", "404 Not Found", "Disk full", "Access denied to local folder", "Error in checkpoint-403.safetensors", "Prepared 401 files", "No such file: an unrelated cache file", "Timeout while hashing local files", "Tokenizing model files"] {
            XCTAssertEqual(UploadRecoveryHint.classify(message: message, sourceExists: true), .other, message)
        }
    }

    func testRestoredFolderDoesNotKeepMissingSourceHint() {
        let priorMessage = "Choose an existing local folder."
        XCTAssertEqual(UploadRecoveryHint.classify(message: priorMessage, sourceExists: false), .missingSource)
        XCTAssertEqual(UploadRecoveryHint.classify(message: priorMessage, sourceExists: true), .other)
    }
}
