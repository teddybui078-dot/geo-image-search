import Testing
import Foundation
@testable import GeoImageSearch

private final class SpyDelaying: RetryDelaying, @unchecked Sendable {
    private(set) var recordedDelays: [TimeInterval] = []

    func delay(_ duration: TimeInterval) async throws {
        recordedDelays.append(duration)
    }
}

private final class Counter: @unchecked Sendable {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}

private struct FixedRetryPolicy: RetryPolicy {
    let maxAttempts: Int
    let retryable: @Sendable (AppError) -> Bool
    let backoffValue: TimeInterval

    func isRetryable(_ error: AppError) -> Bool { retryable(error) }
    func backoff(forAttempt attempt: Int) -> TimeInterval { backoffValue }
}

@Suite struct RetryExecutorTests {
    @Test func succeedsImmediatelyWithoutDelaying() async throws {
        let delaying = SpyDelaying()
        let policy = FixedRetryPolicy(maxAttempts: 3, retryable: { _ in true }, backoffValue: 1.0)

        let result = try await RetryExecutor.run(policy: policy, delaying: delaying) {
            "ok"
        }

        #expect(result == "ok")
        #expect(delaying.recordedDelays.isEmpty)
    }

    @Test func retriesUntilSuccessAndRecordsBackoffPerAttempt() async throws {
        let delaying = SpyDelaying()
        let policy = FixedRetryPolicy(maxAttempts: 5, retryable: { _ in true }, backoffValue: 2.0)
        let counter = Counter()

        let result = try await RetryExecutor.run(policy: policy, delaying: delaying) { () -> Int in
            let attempt = counter.increment()
            if attempt < 3 {
                throw AppError.llmTimeout
            }
            return attempt
        }

        #expect(result == 3)
        #expect(delaying.recordedDelays == [2.0, 2.0])
    }

    @Test func stopsAtMaxAttemptsAndRethrowsOriginalError() async throws {
        let delaying = SpyDelaying()
        let policy = FixedRetryPolicy(maxAttempts: 2, retryable: { _ in true }, backoffValue: 1.0)

        await #expect(throws: AppError.self) {
            try await RetryExecutor.run(policy: policy, delaying: delaying) {
                throw AppError.llmRateLimited
            }
        }

        #expect(delaying.recordedDelays == [1.0])
    }

    @Test func nonRetryableErrorPropagatesWithoutDelaying() async throws {
        let delaying = SpyDelaying()
        let policy = FixedRetryPolicy(maxAttempts: 5, retryable: { _ in false }, backoffValue: 1.0)

        await #expect(throws: AppError.self) {
            try await RetryExecutor.run(policy: policy, delaying: delaying) {
                throw AppError.llmInvalidAPIKey
            }
        }

        #expect(delaying.recordedDelays.isEmpty)
    }

    @Test func nonAppErrorPropagatesImmediately() async throws {
        struct OtherError: Error {}
        let delaying = SpyDelaying()
        let policy = FixedRetryPolicy(maxAttempts: 5, retryable: { _ in true }, backoffValue: 1.0)

        await #expect(throws: OtherError.self) {
            try await RetryExecutor.run(policy: policy, delaying: delaying) {
                throw OtherError()
            }
        }

        #expect(delaying.recordedDelays.isEmpty)
    }
}
