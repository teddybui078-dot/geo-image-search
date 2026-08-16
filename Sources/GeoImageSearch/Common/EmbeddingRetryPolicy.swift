import Foundation

// CoreML inference / thumbnail fetch boundary: transient failures (a
// momentary thumbnail-fetch hiccup, contended CoreML inference) are worth
// a quick retry. A missing asset, an unprovisioned model, or a dimension
// mismatch are permanent for this run — retrying can't fix them.
struct EmbeddingRetryPolicy: RetryPolicy {
    let maxAttempts: Int = 3
    private let baseDelay: TimeInterval = 0.5
    private let maxDelay: TimeInterval = 4.0

    func isRetryable(_ error: AppError) -> Bool {
        guard case .embeddingGenerationFailed(_, let underlying) = error,
              let pipelineError = underlying as? EmbeddingPipelineError
        else {
            return false
        }
        switch pipelineError {
        case .assetNotFound, .modelNotProvisioned, .dimensionMismatch:
            return false
        case .thumbnailUnavailable, .inferenceFailed:
            return true
        }
    }

    func backoff(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
    }
}
