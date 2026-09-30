import Foundation

public enum BridgeProtocolError: Error, LocalizedError, Sendable {
    case oversizedLine(Int)
    case invalidResponse(String)
    public var errorDescription: String? {
        switch self {
        case .oversizedLine(let limit): "Hugging Face returned a response line larger than \(limit) bytes. The response was stopped instead of truncated."
        case .invalidResponse(let message): message
        }
    }
}

/// Preserves framing and UTF-8 across arbitrary pipe reads. Never emits fragments.
public struct JSONLineFramer: Sendable {
    private var pending = Data()
    public let maxLineBytes: Int
    public init(maxLineBytes: Int) { self.maxLineBytes = maxLineBytes }
    public mutating func append(_ data: Data) throws -> [Data] {
        var lines: [Data] = []
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 10) {
            let segment = data[start..<newline]
            guard pending.count + segment.count <= maxLineBytes else { throw BridgeProtocolError.oversizedLine(maxLineBytes) }
            pending.append(contentsOf: segment)
            lines.append(pending)
            pending = Data()
            start = data.index(after: newline)
        }
        guard pending.count + data[start...].count <= maxLineBytes else { throw BridgeProtocolError.oversizedLine(maxLineBytes) }
        pending.append(contentsOf: data[start...])
        return lines
    }
    public mutating func finish() -> Data? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return pending
    }
}

/// Bounds accumulated listings and requires a matching terminal event before use.
public struct HubResponseAccumulator: Sendable {
    private var items: [Data] = []
    private var totalBytes = 0
    private var terminal: Data?
    private var streamed = false
    private var failure: String?
    private let maxItems: Int
    private let maxBytes: Int
    public init(maxItems: Int = 100_000, maxBytes: Int = 32_000_000) {
        self.maxItems = maxItems; self.maxBytes = maxBytes
    }
    public mutating func append(_ line: String) throws {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return } // SDK stderr may be ordinary text.
        if event == "error" { failure = object["message"] as? String; return }
        guard event == "item" || event == "result" else { return }
        guard terminal == nil else { throw BridgeProtocolError.invalidResponse("Hugging Face returned data after the final response.") }
        if event == "item" {
            guard let value = object["data"] else { throw BridgeProtocolError.invalidResponse("Hugging Face returned an invalid listing item.") }
            let encoded = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            guard items.count < maxItems, totalBytes + encoded.count <= maxBytes else {
                throw BridgeProtocolError.invalidResponse("The repository listing is too large to display safely. No partial listing was accepted.")
            }
            items.append(encoded); totalBytes += encoded.count
        } else {
            streamed = object["streamed"] as? Bool == true
            if streamed {
                guard let count = object["count"] as? Int, count == items.count else {
                    throw BridgeProtocolError.invalidResponse("The repository listing was incomplete. Refresh to try again.")
                }
                terminal = Data()
            } else {
                guard items.isEmpty, let value = object["data"] else { throw BridgeProtocolError.invalidResponse("Hugging Face returned an invalid final response.") }
                let encoded = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
                guard encoded.count <= maxBytes else { throw BridgeProtocolError.invalidResponse("Hugging Face returned a response too large to display safely.") }
                terminal = encoded
            }
        }
    }
    public func result(exitStatus: Int32) throws -> Data {
        if let failure { throw BridgeProtocolError.invalidResponse(failure) }
        guard exitStatus == 0, let terminal else {
            throw BridgeProtocolError.invalidResponse("Hugging Face did not return a complete result. Check your connection and refresh.")
        }
        guard streamed else { return terminal }
        var result = Data("[".utf8)
        for (index, item) in items.enumerated() {
            if index > 0 { result.append(44) }
            result.append(item)
        }
        result.append(93)
        return result
    }
}
