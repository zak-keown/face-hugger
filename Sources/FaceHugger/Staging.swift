import Foundation

struct StagedFile: Decodable, Identifiable, Sendable {
    var id: Data { Data(path.utf8) }
    let path: String
    let size: Int64
    let included: Bool
}
struct StagingResult: Decodable, Sendable {
    let files: [StagedFile]
    let includedCount: Int
    let includedBytes: Int64
    let totalCount: Int
    let truncated: Bool
    enum CodingKeys: String, CodingKey {
        case files, truncated
        case includedCount = "included_count", includedBytes = "included_bytes", totalCount = "total_count"
    }
}

struct RemoteComparison: Decodable, Sendable {
    let paths: [String]
    let complete: Bool
    let conflicts: [PathConflict]
}
struct PathConflict: Decodable, Sendable {
    let path: String
    let reason: String
}
