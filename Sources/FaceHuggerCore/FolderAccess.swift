import Foundation

/// Owns one balanced security-scope lifetime. A false start can be normal for
/// an unsandboxed build or an already-accessible URL; callers still validate I/O.
public final class FolderAccess {
    public let url: URL
    public let bookmark: Data?
    private let lock = NSLock()
    private var release: (() -> Void)?

    init(url: URL, bookmark: Data?, release: (() -> Void)?) {
        self.url = url; self.bookmark = bookmark; self.release = release
    }

    public func close() {
        lock.lock()
        let action = release; release = nil
        lock.unlock()
        action?()
    }

    deinit { close() }

    /// Capture a user-selected URL while its implicit access is still valid.
    public static func selected(_ url: URL) throws -> FolderAccess {
        try acquire(url: url, existingBookmark: nil, refresh: true, operations: .system)
    }

    /// Legacy path-only archives remain usable in the direct distribution build.
    /// Invalid saved bookmarks fail explicitly; they never silently fall back to
    /// a potentially different file that happens to occupy the stored path.
    public static func restore(path: String, bookmark: Data?) throws -> FolderAccess {
        try restore(path: path, bookmark: bookmark, operations: .system)
    }

    static func restore(path: String, bookmark: Data?, operations: Operations) throws -> FolderAccess {
        do {
            if let bookmark {
                let resolved = try operations.resolve(bookmark)
                return try acquire(url: resolved.url, existingBookmark: bookmark, refresh: resolved.stale, operations: operations)
            }
            return try acquire(url: URL(fileURLWithPath: path), existingBookmark: nil, refresh: false, operations: operations)
        } catch {
            throw AccessError.unavailable(error.localizedDescription)
        }
    }

    static func acquire(url: URL, existingBookmark: Data?, refresh: Bool, operations: Operations) throws -> FolderAccess {
        let started = operations.start(url)
        do {
            let bookmark = refresh ? try operations.create(url) : existingBookmark
            return FolderAccess(url: url, bookmark: bookmark, release: started ? { operations.stop(url) } : nil)
        } catch {
            if started { operations.stop(url) }
            throw error
        }
    }

    struct Operations {
        var resolve: (Data) throws -> (url: URL, stale: Bool)
        var create: (URL) throws -> Data
        var start: (URL) -> Bool
        var stop: (URL) -> Void
        static var system: Self {
            Self(resolve: { data in
                var stale = false
                let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
                return (url, stale)
            }, create: { url in
                // HF stores resumable metadata under the source; retain read/write access.
                try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            }, start: { $0.startAccessingSecurityScopedResource() }, stop: { $0.stopAccessingSecurityScopedResource() })
        }
    }

    public enum AccessError: LocalizedError {
        case unavailable(String)
        public var errorDescription: String? {
            switch self {
            case .unavailable(let detail): "Folder access could not be restored. Reconnect its drive or choose Locate folder to grant access again. \(detail)"
            }
        }
    }
}
