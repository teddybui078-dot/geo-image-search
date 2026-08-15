import Foundation

// PhotosKit/iCloud boundary: fetch failures are usually a transient local
// I/O or iCloud network hiccup, so retries are quick and capped low.
// Permission denial is a user-action problem (grant access in System
// Settings), not something a retry can fix.
struct PhotosRetryPolicy: RetryPolicy {
    let maxAttempts: Int = 3
    private let baseDelay: TimeInterval = 0.5
    private let maxDelay: TimeInterval = 4.0

    func isRetryable(_ error: AppError) -> Bool {
        switch error {
        case .photosFetchFailed:
            return true
        default:
            return false
        }
    }

    func backoff(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2.0, Double(attempt - 1)), maxDelay)
    }
}
