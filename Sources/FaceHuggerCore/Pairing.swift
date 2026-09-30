import Foundation

/// A manually invoked route. Credentials and transfer state are never stored here.
public struct SavedPairing: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var source: String
    public var sourceBookmark: Data?
    public var repo: HubRepo
    public var destination: String
    public var includes: [String]
    public var excludes: [String]
    public init(name: String, source: String, repo: HubRepo, destination: String, includes: [String], excludes: [String], sourceBookmark: Data? = nil) {
        self.sourceBookmark = sourceBookmark
        id = UUID(); self.name = name; self.source = source; self.repo = repo
        self.destination = destination; self.includes = includes; self.excludes = excludes
    }
}

public struct PairingArchive: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> [SavedPairing] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SavedPairing].self, from: Data(contentsOf: url))
    }
    public func save(_ pairings: [SavedPairing]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(pairings).write(to: url, options: .atomic)
    }
}
