import Testing
@testable import GeoImageSearch

private struct FakeUnderlyingError: Error {}

@Suite struct GeocodingRetryPolicyTests {
    private let policy = GeocodingRetryPolicy()

    @Test func rateLimitedIsRetryable() {
        #expect(policy.isRetryable(.geocodingRateLimited))
    }

    @Test func genericFailureIsRetryable() {
        #expect(policy.isRetryable(.geocodingFailed(underlying: FakeUnderlyingError())))
    }

    @Test func errorsFromOtherBoundariesAreNotRetryable() {
        #expect(!policy.isRetryable(.photosPermissionDenied))
        #expect(!policy.isRetryable(.llmInvalidAPIKey))
    }

    @Test func maxAttemptsIsFour() {
        #expect(policy.maxAttempts == 4)
    }

    @Test func backoffGrowsExponentiallyAndCaps() {
        #expect(policy.backoff(forAttempt: 1) == 1.0)
        #expect(policy.backoff(forAttempt: 2) == 2.0)
        #expect(policy.backoff(forAttempt: 3) == 4.0)
        #expect(policy.backoff(forAttempt: 4) == 8.0)
        #expect(policy.backoff(forAttempt: 20) == 30.0)
    }
}
