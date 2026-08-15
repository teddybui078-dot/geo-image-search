import Testing
import Foundation
@testable import GeoImageSearch

private struct FakeUnderlyingError: Error, LocalizedError {
    var errorDescription: String? { "boom" }
}

@Suite struct AppErrorTests {
    @Test func permissionDeniedIsError() {
        #expect(AppError.photosPermissionDenied.severity == .error)
        #expect(AppError.photosPermissionDenied.logDescription == "Photos library access denied")
    }

    @Test func rateLimitedCasesAreWarnings() {
        #expect(AppError.geocodingRateLimited.severity == .warning)
        #expect(AppError.llmRateLimited.severity == .warning)
        #expect(AppError.llmTimeout.severity == .warning)
    }

    @Test func invalidAPIKeyIsError() {
        #expect(AppError.llmInvalidAPIKey.severity == .error)
    }

    @Test func underlyingErrorsAreIncludedInDescription() {
        let error = AppError.photosFetchFailed(underlying: FakeUnderlyingError())
        #expect(error.logDescription.contains("boom"))
        #expect(error.severity == .error)
    }

    @Test func embeddingFailureIncludesAssetID() {
        let error = AppError.embeddingGenerationFailed(assetID: "asset-42", underlying: FakeUnderlyingError())
        #expect(error.logDescription.contains("asset-42"))
        #expect(error.logDescription.contains("boom"))
    }

    @Test func webviewLoadFailedIsError() {
        #expect(AppError.webviewLoadFailed.severity == .error)
        #expect(AppError.webviewLoadFailed.logDescription == "Globe webview failed to load")
    }
}
