import Foundation

public struct NativeStagedFile: Codable, Sendable {
    public let path: String
    public let size: Int64
    public let included: Bool
}

public struct NativeScanResult: Codable, Sendable {
    public let files: [NativeStagedFile]
    public let includedCount: Int
    public let includedBytes: Int64
    public let totalCount: Int
    public let truncated: Bool
    enum CodingKeys: String, CodingKey {
        case files, truncated
        case includedCount = "included_count", includedBytes = "included_bytes", totalCount = "total_count"
    }
}

public enum NativeScanError: LocalizedError {
    case invalidSource, externalLink(String), unreadable(String), invalidPath(String)
    public var errorDescription: String? {
        switch self {
        case .invalidSource: "Choose an existing local folder to upload."
        case .externalLink(let path): "Linked file '\(path)' points outside the selected folder."
        case .unreadable(let path): "Cannot read '\(path)'. Check permissions and broken links."
        case .invalidPath(let path): "The file name '\(path)' cannot be used as a repository path."
        }
    }
}

public enum NativeScanner {
    /// HF-style case-sensitive wildcards: `*` crosses folder boundaries, and a
    /// trailing slash selects the whole folder. Backslashes normalize to slashes.
    public static func matches(_ path: String, pattern: String) -> Bool {
        var normalized = pattern.replacingOccurrences(of: "\\", with: "/")
        if normalized.hasSuffix("/") { normalized += "*" }
        let tokens = wildcardTokens(Array(normalized.unicodeScalars.map(\.value)))
        let scalars = path.replacingOccurrences(of: "\\", with: "/").unicodeScalars.map(\.value)
        // Bounded rolling state avoids exponential wildcard backtracking.
        var previous = Array(repeating: false, count: tokens.count + 1)
        previous[0] = true
        for index in tokens.indices {
            if case .star = tokens[index] { previous[index + 1] = previous[index] }
        }
        for scalar in scalars {
            var current = Array(repeating: false, count: tokens.count + 1)
            for index in tokens.indices {
                switch tokens[index] {
                case .star: current[index + 1] = current[index] || previous[index + 1]
                case .any: current[index + 1] = previous[index]
                case .literal(let value): current[index + 1] = previous[index] && scalar == value
                case .characterClass(let literals, let ranges, let negated):
                    let member = literals.contains(scalar) || ranges.contains { $0.contains(scalar) }
                    current[index + 1] = previous[index] && (member != negated)
                }
            }
            previous = current
        }
        return previous[tokens.count]
    }

    private enum WildcardToken {
        case star, any, literal(UInt32)
        case characterClass(Set<UInt32>, [ClosedRange<UInt32>], Bool)
    }

    /// Direct scalar matcher for Python fnmatchcase's documented wildcard syntax.
    /// Bracket range normalization is adapted from CPython Lib/fnmatch.py
    /// (_translate): Copyright Python Software Foundation, PSF License Version 2.
    /// See Resources/PythonFnmatchLicense.txt for attribution and license text.
    /// Bracket ranges discard descending endpoints; '^' and POSIX classes are literal.
    private static func wildcardTokens(_ pattern: [UInt32]) -> [WildcardToken] {
        var result: [WildcardToken] = []
        var index = 0
        while index < pattern.count {
            let value = pattern[index]
            index += 1
            switch value {
            case 42:
                if case .star? = result.last { continue }
                result.append(.star)
            case 63: result.append(.any)
            case 91:
                var end = index
                if end < pattern.count && pattern[end] == 33 { end += 1 }
                if end < pattern.count && pattern[end] == 93 { end += 1 }
                while end < pattern.count && pattern[end] != 93 { end += 1 }
                guard end < pattern.count else { result.append(.literal(value)); continue }
                let body = Array(pattern[index..<end])
                index = end + 1
                var chunks: [[UInt32]] = []
                var start = 0
                var search = body.first == 33 ? 2 : 1
                while search < body.count, let hyphen = body[search...].firstIndex(of: 45) {
                    chunks.append(Array(body[start..<hyphen]))
                    start = hyphen + 1
                    search = hyphen + 3
                }
                if start < body.count { chunks.append(Array(body[start...])) }
                else if !chunks.isEmpty { chunks[chunks.count - 1].append(45) }
                if chunks.count > 1 {
                    for part in stride(from: chunks.count - 1, through: 1, by: -1) {
                        if let lower = chunks[part - 1].last, let upper = chunks[part].first, lower > upper {
                            chunks[part - 1].removeLast()
                            chunks[part - 1].append(contentsOf: chunks[part].dropFirst())
                            chunks.remove(at: part)
                        }
                    }
                }
                let negated = chunks.first?.first == 33
                if negated { chunks[0].removeFirst() }
                var ranges: [ClosedRange<UInt32>] = []
                if chunks.count > 1 {
                    for part in 1..<chunks.count {
                        if let lower = chunks[part - 1].last, let upper = chunks[part].first { ranges.append(lower...upper) }
                    }
                }
                result.append(.characterClass(Set(chunks.flatMap { $0 }), ranges, negated))
            default: result.append(.literal(value))
            }
        }
        return result
    }

    public static func scan(source: URL, includes: [String] = [], excludes: [String] = [], limit: Int? = 2000) throws -> NativeScanResult {
        var files: [NativeStagedFile] = []
        var count = 0, included = 0
        var bytes: Int64 = 0
        try walk(source: source, includes: includes, excludes: excludes) { file in
            count += 1
            if file.included { included += 1; bytes += file.size }
            if limit == nil || files.count < max(0, limit!) { files.append(file) }
        }
        return NativeScanResult(files: files.sorted { $0.path < $1.path }, includedCount: included,
                                includedBytes: bytes, totalCount: count, truncated: count > files.count)
    }

    /// Reads only metadata. Directory enumeration is streamed; preview limits do
    /// not change totals or hide a bad included file later in the walk.
    public static func walk(source: URL, includes: [String] = [], excludes: [String] = [], onFile: (NativeStagedFile) throws -> Void) throws {
        let root = source.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard root.isFileURL, FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw NativeScanError.invalidSource }
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey], options: [], errorHandler: { url, _ in
            enumerationError = NativeScanError.unreadable(url.lastPathComponent); return false
        }) else { throw NativeScanError.invalidSource }
        let rootPrefix = root.path == "/" ? "/" : root.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/"
        let absolutePrefix = rootPrefix.hasPrefix("/") ? rootPrefix : "/" + rootPrefix
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let childPath = url.standardizedFileURL.path
            guard childPath.utf8.starts(with: absolutePrefix.utf8) else { throw NativeScanError.unreadable(url.lastPathComponent) }
            let relative = String(decoding: childPath.utf8.dropFirst(absolutePrefix.utf8.count), as: UTF8.self)
            let components = relative.split(separator: "/")
            if components.contains(".git") || zip(components, components.dropFirst()).contains(where: { $0 == ".cache" && $1 == "huggingface" }) {
                enumerator.skipDescendants(); continue
            }
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    let resolved = url.resolvingSymlinksInPath()
                    let target = try resolved.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])
                    if target.isDirectory == true { continue }
                    guard target.isRegularFile == true else { throw NativeScanError.unreadable(relative) }
                    guard resolved.path.utf8.starts(with: absolutePrefix.utf8) else { throw NativeScanError.externalLink(relative) }
                    try emit(relative, size: target.fileSize ?? 0, url: url, includes: includes, excludes: excludes, onFile: onFile)
                } else if values.isRegularFile == true {
                    try emit(relative, size: values.fileSize ?? 0, url: url, includes: includes, excludes: excludes, onFile: onFile)
                }
            } catch let error as NativeScanError { throw error }
            catch is CancellationError { throw CancellationError() }
            catch { throw error }
        }
        if let enumerationError { throw enumerationError }
    }

    private static func emit(_ path: String, size: Int, url: URL, includes: [String], excludes: [String], onFile: (NativeStagedFile) throws -> Void) throws {
        let included = (includes.isEmpty || includes.contains { matches(path, pattern: $0) }) && !excludes.contains { matches(path, pattern: $0) }
        if included {
            guard !path.contains("\\"), path.rangeOfCharacter(from: .controlCharacters) == nil else { throw NativeScanError.invalidPath(path) }
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw NativeScanError.unreadable(path) }
        }
        try onFile(NativeStagedFile(path: path, size: Int64(size), included: included))
    }
}
