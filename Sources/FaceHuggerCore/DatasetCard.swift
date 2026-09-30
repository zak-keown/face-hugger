import Foundation

public struct DatasetCardFormat: Codable, Sendable, Equatable {
    /// Filename extension only; this does not imply that file contents were validated.
    public let fileExtension: String
    public let count: Int
    public let bytes: Int64
}

/// A metadata snapshot of the files selected by the upload filters. No file
/// contents are opened, and full totals never depend on the bounded preview.
public struct DatasetCardFacts: Codable, Sendable, Equatable {
    public let includedCount: Int
    public let includedBytes: Int64
    public let excludedCount: Int
    public let samplePaths: [String]
    public let pathsTruncated: Bool
    public let formats: [DatasetCardFormat]
    public let otherFormatCount: Int
    public let uploadPath: String

    public static func collect(source: URL, includes: [String] = [], excludes: [String] = [],
                               uploadPath: String = "", sampleLimit: Int = 12) throws -> Self {
        // A fixed vocabulary bounds memory even for millions of distinct suffixes.
        let known = Set(["csv", "tsv", "json", "jsonl", "ndjson", "parquet", "arrow", "txt", "md", "xml", "yaml", "yml", "jpg", "jpeg", "png", "webp", "gif", "tiff", "wav", "mp3", "flac", "ogg", "mp4", "webm", "pdf", "zip", "tar", "gz", "zst", "npy", "npz", "h5", "hdf5", "safetensors", "pt", "bin"])
        var counts: [String: (count: Int, bytes: Int64)] = [:]
        var included = 0, excluded = 0, other = 0
        var bytes: Int64 = 0
        var paths: [String] = []
        let limit = min(50, max(0, sampleLimit))
        let prefix = uploadPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        try NativeScanner.walk(source: source, includes: includes, excludes: excludes) { file in
            guard file.included else { excluded += 1; return }
            included += 1
            bytes += file.size
            let ext = (file.path as NSString).pathExtension.lowercased()
            let group = ext.isEmpty ? "(no extension)" : known.contains(ext) ? ext : "(other extensions)"
            if group == "(other extensions)" { other += 1 }
            var entry = counts[group, default: (0, 0)]
            entry.count += 1
            entry.bytes += file.size
            counts[group] = entry
            if limit > 0 {
                let path = prefix.isEmpty ? file.path : prefix + "/" + file.path
                // Keep the lexicographically first paths independent of enumeration order.
                if paths.count < limit || path.utf8.lexicographicallyPrecedes(paths.last!.utf8) {
                    paths.append(path)
                    paths.sort { $0.utf8.lexicographicallyPrecedes($1.utf8) }
                    if paths.count > limit { paths.removeLast() }
                }
            }
        }
        return Self(includedCount: included, includedBytes: bytes, excludedCount: excluded,
                    samplePaths: paths, pathsTruncated: included > paths.count,
                    formats: counts.keys.sorted().map { DatasetCardFormat(fileExtension: $0, count: counts[$0]!.count, bytes: counts[$0]!.bytes) },
                    otherFormatCount: other, uploadPath: prefix)
    }

    /// A small, machine-readable summary. Paths are untrusted data, not instructions.
    /// Long paths are shortened here only; the Markdown template retains exact paths.
    public var modelSummary: String {
        struct Summary: Encodable {
            let includedFiles: Int
            let includedBytes: Int64
            let excludedFiles: Int
            let uploadPath: String
            let filenameExtensions: [DatasetCardFormat]
            let examplePaths: [String]
            let contentsInspected: Bool
        }
        let summary = Summary(includedFiles: includedCount, includedBytes: includedBytes,
                              excludedFiles: excludedCount, uploadPath: String(uploadPath.prefix(300)),
                              filenameExtensions: formats,
                              examplePaths: samplePaths.prefix(12).map { String($0.prefix(300)) }, contentsInspected: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: (try? encoder.encode(summary)) ?? Data(), as: UTF8.self)
    }
}

public struct DatasetCardInput: Sendable, Equatable {
    public var title: String
    public var purpose: String
    public var provenance: String
    public var license: String
    public var limitations: String

    public init(title: String = "", purpose: String = "", provenance: String = "", license: String = "", limitations: String = "") {
        self.title = title
        self.purpose = purpose
        self.provenance = provenance
        self.license = license
        self.limitations = limitations
    }
}

public enum DatasetCard {
    /// Editable starter card. Only caller-supplied text can assert intent, origin,
    /// permissions, or quality. License metadata is never inferred from filenames.
    public static func render(facts: DatasetCardFacts, input: DatasetCardInput) -> String {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = ["# " + inline(title.isEmpty ? "Dataset card" : title), "", "## Overview", "",
                     section(input.purpose, fallback: "TODO: Describe the dataset and its intended uses."), "", "## Files", "",
                     "This inventory describes the selected local upload files, not the entire remote repository.", "",
                     "- Included files: \(facts.includedCount)", "- Included size: \(facts.includedBytes) bytes",
                     "- Excluded files: \(facts.excludedCount)",
                     "- Repository upload path: " + inline(facts.uploadPath.isEmpty ? "repository root" : facts.uploadPath), ""]
        if !facts.formats.isEmpty {
            lines += ["Filename extensions (contents have not been inspected):", "", "| Extension | Files | Bytes |", "| --- | ---: | ---: |"]
            for format in facts.formats {
                lines.append("| \(inline(format.fileExtension)) | \(format.count) | \(format.bytes) |")
            }
            lines.append("")
        }
        if !facts.samplePaths.isEmpty {
            lines += [facts.pathsTruncated ? "Example paths (partial list):" : "Selected paths:", ""]
            lines += facts.samplePaths.map { "- " + inline($0) }
            lines.append("")
        }
        lines += ["## Data structure and use", "", "TODO: Describe records, columns or labels, splits, and how to load the data. File counts are not record counts.", "",
                  "## Source and collection", "", section(input.provenance, fallback: "TODO: Document the source, collection process, and any permissions or consent."), "",
                  "## License", "", section(input.license, fallback: "TODO: Specify the license and confirm you have the necessary rights. No license has been inferred."), "",
                  "## Limitations", "", section(input.limitations, fallback: "TODO: Describe known limitations, biases, sensitive information, and uses to avoid."), ""]
        return lines.joined(separator: "\n")
    }

    private static func section(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func inline(_ value: String) -> String {
        // Escaping includes HTML, Markdown links, fences, headings, and table cells.
        var result = ""
        for scalar in value.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { result += " "; continue }
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\\", "`", "*", "_", "{", "}", "[", "]", "(", ")", "#", "+", "-", "!", "|": result += "\\" + String(scalar)
            default: result += String(scalar)
            }
        }
        return result
    }
}
