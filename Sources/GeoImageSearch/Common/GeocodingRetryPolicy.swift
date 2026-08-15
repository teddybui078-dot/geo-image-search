import Foundation

// CLGeocoder boundary: rate limiting is the dominant failure mode for a
// personal-library ingest run, so this policy allows more attempts with a
// longer backoff ceiling than PhotosRetryPolicy — give the rate limit time
// to actually clear instead of hammering it.
struct GeocodingRetryPolicy: RetryPolicy {
    let maxAttempts: Int = 4
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 30.0

    func isRetryable(_ error: AppError) -> Bool {
        switch error {
        case .geocodingRateLimited, .geocodingFailed:
            return true
        default:
            return false
        }
    }

    func backoff(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
    }
}
