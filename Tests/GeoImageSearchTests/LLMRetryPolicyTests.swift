import Testing
@testable import GeoImageSearch

@Suite struct LLMRetryPolicyTests {
    private let policy = LLMRetryPolicy()

    @Test func timeoutIsRetryable() {
        #expect(policy.isRetryable(.llmTimeout))
    }

    @Test func rateLimitedIsRetryable() {
        #expect(policy.isRetryable(.llmRateLimited))
    }

    @Test func invalidAPIKeyIsNotRetryable() {
        #expect(!policy.isRetryable(.llmInvalidAPIKey))
    }

    @Test func errorsFromOtherBoundariesAreNotRetryable() {
        #expect(!policy.isRetryable(.photosPermissionDenied))
        #expect(!policy.isRetryable(.geocodingRateLimited))
    }

    @Test func maxAttemptsIsFive() {
        #expect(policy.maxAttempts == 5)
    }

    @Test func backoffGrowsExponentiallyAndCaps() {
        #expect(policy.backoff(forAttempt: 1) == 2.0)
        #expect(policy.backoff(forAttempt: 2) == 4.0)
        #expect(policy.backoff(forAttempt: 3) == 8.0)
        #expect(policy.backoff(forAttempt: 4) == 16.0)
        #expect(policy.backoff(forAttempt: 5) == 32.0)
        #expect(policy.backoff(forAttempt: 20) == 60.0)
    }
}
