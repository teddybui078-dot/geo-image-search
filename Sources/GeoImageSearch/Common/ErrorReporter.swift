import Foundation
import os

// The sink is a separate abstraction from ErrorReporter itself so tests can
// substitute a spy instead of asserting against real OSLog output, which
// isn't practical to intercept in unit tests.
protocol ErrorLogSink: Sendable {
    func log(_ message: String, severity: ErrorSeverity)
}

struct OSLogErrorSink: ErrorLogSink {
    private let logger: Logger

    init(subsystem: String = "com.geoimagesearch.app", category: String = "errors") {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func log(_ message: String, severity: ErrorSeverity) {
        switch severity {
        case .warning:
            logger.notice("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        }
    }
}

// Shared error-reporting surface across PhotosKit/CLGeocoder/LLM boundaries —
// consistent UI/logging presentation, but see RetryPolicy for per-boundary
// retry logic, which is intentionally not unified here.
final class ErrorReporter: ErrorReporting, Sendable {
    private let sink: ErrorLogSink

    init(sink: ErrorLogSink = OSLogErrorSink()) {
        self.sink = sink
    }

    func report(_ error: AppError, context: String) {
        sink.log("[\(context)] \(error.logDescription)", severity: error.severity)
    }
}
