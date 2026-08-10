import Foundation

// OpenAI API boundary: timeouts and rate limits are transient and worth
// riding out with a long exponential backoff (external network call, worst
// tail latency of the three boundaries). An invalid API key is a
// configuration problem — retrying never fixes it, so it's excluded.
struct LLMRetryPolicy: RetryPolicy {
    let maxAttempts: Int = 5

    func isRetryable(_ error: AppError) -> Bool {
        switch error {
        case .llmTimeout, .llmRateLimited:
            return true
        default:
            return false
        }
    }

    func backoff(forAttempt attempt: Int) -> TimeInterval {
        min(2.0 * pow(2.0, Double(attempt - 1)), 60.0)
    }
}
