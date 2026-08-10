import Testing
import Foundation
@testable import GeoImageSearch

private struct FakeUnderlyingError: Error {}

@Suite struct PhotosRetryPolicyTests {
    private let policy = PhotosRetryPolicy()

    @Test func fetchFailedIsRetryable() {
        #expect(policy.isRetryable(.photosFetchFailed(underlying: FakeUnderlyingError())))
    }

    @Test func permissionDeniedIsNotRetryable() {
        #expect(!policy.isRetryable(.photosPermissionDenied))
    }

    @Test func errorsFromOtherBoundariesAreNotRetryable() {
        #expect(!policy.isRetryable(.llmTimeout))
        #expect(!policy.isRetryable(.geocodingRateLimited))
    }

    @Test func maxAttemptsIsThree() {
        #expect(policy.maxAttempts == 3)
    }

    @Test func backoffGrowsExponentiallyAndCaps() {
        #expect(policy.backoff(forAttempt: 1) == 0.5)
        #expect(policy.backoff(forAttempt: 2) == 1.0)
        #expect(policy.backoff(forAttempt: 3) == 2.0)
        #expect(policy.backoff(forAttempt: 4) == 4.0)
        #expect(policy.backoff(forAttempt: 10) == 4.0)
    }
}
