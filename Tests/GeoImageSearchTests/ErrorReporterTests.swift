import Testing
@testable import GeoImageSearch

private final class SpyErrorLogSink: ErrorLogSink, @unchecked Sendable {
    private(set) var loggedMessages: [(message: String, severity: ErrorSeverity)] = []

    func log(_ message: String, severity: ErrorSeverity) {
        loggedMessages.append((message, severity))
    }
}

@Suite struct ErrorReporterTests {
    @Test func reportsContextAndDescriptionThroughTheSink() {
        let sink = SpyErrorLogSink()
        let reporter = ErrorReporter(sink: sink)

        reporter.report(.photosPermissionDenied, context: "PhotosIngestion.start")

        #expect(sink.loggedMessages.count == 1)
        let logged = sink.loggedMessages[0]
        #expect(logged.message == "[PhotosIngestion.start] Photos library access denied")
        #expect(logged.severity == .error)
    }

    @Test func routesSeverityFromTheError() {
        let sink = SpyErrorLogSink()
        let reporter = ErrorReporter(sink: sink)

        reporter.report(.llmRateLimited, context: "Agent.ask")

        #expect(sink.loggedMessages[0].severity == .warning)
    }

    @Test func reportsMultipleErrorsInOrder() {
        let sink = SpyErrorLogSink()
        let reporter = ErrorReporter(sink: sink)

        reporter.report(.geocodingRateLimited, context: "Geocoder.reverseGeocode")
        reporter.report(.webviewLoadFailed, context: "Globe.load")

        #expect(sink.loggedMessages.count == 2)
        #expect(sink.loggedMessages[0].message.contains("Geocoding rate limited"))
        #expect(sink.loggedMessages[1].message.contains("Globe webview failed to load"))
    }
}
