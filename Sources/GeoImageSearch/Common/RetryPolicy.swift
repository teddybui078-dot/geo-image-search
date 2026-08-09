import Foundation

// Per-boundary retry policy (PhotosKit/CLGeocoder/LLM have different failure
// semantics — refined from a fully-unified design after outside-voice review).
protocol RetryPolicy {
    var maxAttempts: Int { get }
    func isRetryable(_ error: Error) -> Bool
}
