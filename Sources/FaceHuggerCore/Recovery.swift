import Foundation

/// Suggested next steps, not definitive diagnoses of arbitrary CLI error text.
public enum UploadRecoveryHint: Equatable, Sendable {
    case authentication, network, missingSource, other

    public static func classify(message: String, sourceExists: Bool) -> Self {
        guard sourceExists else { return .missingSource }
        let text = message.lowercased()
        let accountPhrases = ["unauthorized", "forbidden", "invalid token", "invalid credentials", "authentication failed", "authentication required", "token has expired", "token expired", "insufficient permissions", "write access"]
        if accountPhrases.contains(where: text.contains) || text.range(of: #"\b(401|403)\s+(client error|unauthorized|forbidden)\b|\b(http|status(?: code)?)\s*[:=]?\s*(401|403)\b"#, options: .regularExpression) != nil {
            return .authentication
        }
        let networkPhrases = ["connectionerror", "connecterror", "connecttimeout", "readtimeout", "connection refused", "connection reset", "connection aborted", "connection timed out", "read timed out", "temporary failure in name resolution", "name or service not known", "network is unreachable", "network is down", "nodename nor servname provided"]
        if networkPhrases.contains(where: text.contains) { return .network }
        return .other
    }

    public var guidance: String {
        switch self {
        case .authentication:
            "This may be an account or repository permission issue. Check your account and token’s write access in Settings, then retry."
        case .network:
            "This may be a connection issue. Check your network, then retry. Already-uploaded content can be reused."
        case .missingSource:
            "The source folder is unavailable. Reconnect its drive or locate the original folder, then resume."
        case .other:
            "Review the error and activity log, then retry when ready. Committed files remain on Hugging Face."
        }
    }
}
