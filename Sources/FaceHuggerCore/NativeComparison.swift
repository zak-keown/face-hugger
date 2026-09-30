import Foundation

public struct NativePathConflict: Codable, Sendable {
    public let path: String
    public let reason: String
}
public struct NativeComparisonResult: Codable, Sendable {
    public let paths: [String]
    public let complete: Bool
    public let conflicts: [NativePathConflict]
}

/// Bounded preview index. An incomplete remote listing never proves a path new.
public struct NativePathComparison: Sendable {
    private let targets: [Data: String]
    private let ancestors: [Data: [String]]
    private var found: [Data: String] = [:]
    private var conflicts: [Data: NativePathConflict] = [:]
    public init(paths: [String], destination: String) {
        let prefix = destination.isEmpty ? "" : destination + "/"
        var targets: [Data: String] = [:], ancestors: [Data: [String]] = [:]
        for path in paths {
            let full = prefix + path
            targets[Data(full.utf8)] = path
            var components = full.split(separator: "/").map(String.init)
            while components.count > 1 {
                components.removeLast()
                ancestors[Data(components.joined(separator: "/").utf8), default: []].append(path)
            }
        }
        self.targets = targets; self.ancestors = ancestors
    }
    public mutating func observe(path: String, isDirectory: Bool) {
        if let local = targets[Data(path.utf8)] {
            found[Data(local.utf8)] = local
            if isDirectory { conflicts[Data(local.utf8)] = NativePathConflict(path: local, reason: "Remote path '\(path)' is a folder, but the staged path is a file.") }
        }
        if !isDirectory {
            for local in ancestors[Data(path.utf8)] ?? [] {
                conflicts[Data(local.utf8)] = NativePathConflict(path: local, reason: "Remote path '\(path)' is a file, but this upload needs it as a folder.")
            }
        }
    }
    public func result(complete: Bool) -> NativeComparisonResult {
        NativeComparisonResult(paths: found.values.sorted(), complete: complete,
                               conflicts: conflicts.values.sorted { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) })
    }
}
