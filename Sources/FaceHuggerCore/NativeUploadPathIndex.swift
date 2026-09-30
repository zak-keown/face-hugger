import Foundation
import SQLite3

/// Disk-backed full-upload preflight. Preview limits never reduce coverage.
public final class NativeUploadPathIndex: @unchecked Sendable {
    private let lock = NSLock()
    private var database: OpaquePointer?
    private let prefix: String
    public init(url: URL, destination: String) throws {
        prefix = destination.isEmpty ? "" : destination + "/"
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }; database = nil
            throw Self.failure()
        }
        do {
            try execute("PRAGMA cache_size = -2048")
            try execute("CREATE TABLE targets (full TEXT PRIMARY KEY COLLATE BINARY, relative TEXT NOT NULL) WITHOUT ROWID")
            try execute("BEGIN TRANSACTION")
        } catch { if let database { sqlite3_close(database) }; database = nil; throw error }
    }
    deinit { if let database { sqlite3_close(database) } }
    public func close() throws {
        try lock.withLock {
            guard let database else { return }
            try execute("COMMIT")
            guard sqlite3_close(database) == SQLITE_OK else { throw Self.failure() }
            self.database = nil
        }
    }
    public func add(path: String) throws {
        try lock.withLock {
            try query("INSERT INTO targets(full,relative) VALUES (?,?)", values: [prefix + path, path]) { _ in }
        }
    }
    public func observe(path: String, isDirectory: Bool) throws -> NativePathConflict? {
        try lock.withLock {
            var relative: String?
            if isDirectory {
                try query("SELECT relative FROM targets WHERE full = ? LIMIT 1", values: [path]) { relative = $0 }
            } else {
                // '/' is immediately below '0' in binary UTF-8 order, so the
                // range covers descendants without LIKE wildcard ambiguities.
                try query("SELECT relative FROM targets WHERE full >= ? AND full < ? LIMIT 1", values: [path + "/", path + "0"]) { relative = $0 }
            }
            guard let relative else { return nil }
            return NativePathConflict(path: relative, reason: isDirectory
                ? "Remote path '\(path)' is a folder, but the staged path is a file."
                : "Remote path '\(path)' is a file, but this upload needs it as a folder.")
        }
    }
    private func execute(_ sql: String) throws {
        guard let database, sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw Self.failure() }
    }
    private func query(_ sql: String, values: [String], row: (String) -> Void) throws {
        guard let database else { throw Self.failure() }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw Self.failure() }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let status = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            guard status == SQLITE_OK else { throw Self.failure() }
        }
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                if let text = sqlite3_column_text(statement, 0) { row(String(cString: text)) }
            case SQLITE_DONE: return
            default: throw Self.failure()
            }
        }
    }
    private static func failure() -> NSError {
        NSError(domain: "NativeUploadPathIndex", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not maintain the upload path index. Check available disk space and retry."])
    }
}
