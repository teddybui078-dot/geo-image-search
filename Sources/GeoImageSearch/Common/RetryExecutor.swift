import Foundation

// Delay is injectable so callers (and tests) don't have to depend on real
// wall-clock time — RetryExecutorTests substitutes a spy that records
// durations instead of sleeping.
protocol RetryDelaying: Sendable {
    func delay(_ duration: TimeInterval) async throws
}

struct TaskSleepDelaying: RetryDelaying {
    func delay(_ duration: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
    }
}

// Shared retry loop so each boundary (PhotosKit, CLGeocoder, OpenAI) drives
// its own RetryPolicy without hand-rolling its own attempt-counting/backoff
// loop. Only AppError is retried against the policy; any other thrown error
// propagates immediately since a RetryPolicy only knows how to judge
// AppError cases.
enum RetryExecutor {
    static func run<Value: Sendable>(
        policy: any RetryPolicy,
        delaying: any RetryDelaying = TaskSleepDelaying(),
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        var attempt = 1
        while true {
            do {
                return try await operation()
            } catch let error as AppError {
                guard attempt < policy.maxAttempts, policy.isRetryable(error) else {
                    throw error
                }
                try await delaying.delay(policy.backoff(forAttempt: attempt))
                attempt += 1
            }
        }
    }
}
