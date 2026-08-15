import Foundation

// Per-boundary retry policy (PhotosKit/CLGeocoder/LLM have different failure
// semantics — refined from a fully-unified design after outside-voice
// review, see DESIGN.md's Architecture Decisions). Shape locked by
// CONTRACT.md; concrete policies live in their own files (PhotosRetryPolicy,
// GeocodingRetryPolicy, LLMRetryPolicy).
protocol RetryPolicy: Sendable {
    var maxAttempts: Int { get }
    func isRetryable(_ error: AppError) -> Bool
    func backoff(forAttempt attempt: Int) -> TimeInterval
}
