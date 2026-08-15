import Foundation

// Cases and shape are locked by CONTRACT.md's "Error handling" section —
// every other feature worktree imports this type, so changing a case here
// is a breaking change that needs coordination (see CONTRACT.md's
// "Changing the contract").
enum AppError: Error {
    case photosPermissionDenied
    case photosFetchFailed(underlying: Error)
    case geocodingRateLimited
    case geocodingFailed(underlying: Error)
    case llmTimeout
    case llmRateLimited
    case llmInvalidAPIKey
    case embeddingGenerationFailed(assetID: String, underlying: Error)
    case webviewLoadFailed
}

// Severity is intentionally decoupled from OSLogType (a platform logging
// concept) so this file stays a plain Foundation domain type, matching
// CONTRACT.md's literal `import Foundation` — ErrorReporter maps this to
// OSLogType at the logging boundary instead.
enum ErrorSeverity {
    case warning
    case error
}

extension AppError {
    var severity: ErrorSeverity {
        switch self {
        case .photosPermissionDenied,
             .photosFetchFailed,
             .geocodingFailed,
             .llmInvalidAPIKey,
             .embeddingGenerationFailed,
             .webviewLoadFailed:
            return .error
        case .geocodingRateLimited, .llmTimeout, .llmRateLimited:
            return .warning
        }
    }

    // Consistent, human-readable text so every reporting/logging call site
    // formats the same error the same way, instead of each boundary
    // writing its own message.
    var logDescription: String {
        switch self {
        case .photosPermissionDenied:
            return "Photos library access denied"
        case .photosFetchFailed(let underlying):
            return "Photos fetch failed: \(underlying.localizedDescription)"
        case .geocodingRateLimited:
            return "Geocoding rate limited"
        case .geocodingFailed(let underlying):
            return "Geocoding failed: \(underlying.localizedDescription)"
        case .llmTimeout:
            return "LLM request timed out"
        case .llmRateLimited:
            return "LLM rate limited"
        case .llmInvalidAPIKey:
            return "LLM API key is invalid"
        case .embeddingGenerationFailed(let assetID, let underlying):
            return "Embedding generation failed for asset \(assetID): \(underlying.localizedDescription)"
        case .webviewLoadFailed:
            return "Globe webview failed to load"
        }
    }
}
