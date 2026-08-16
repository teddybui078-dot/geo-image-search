import Testing
@testable import GeoImageSearch

private struct FakeUnderlyingError: Error {}

@Suite struct EmbeddingRetryPolicyTests {
    private let policy = EmbeddingRetryPolicy()

    @Test func thumbnailUnavailableIsRetryable() {
        let error = AppError.embeddingGenerationFailed(
            assetID: "asset-1",
            underlying: EmbeddingPipelineError.thumbnailUnavailable(assetLocalIdentifier: "asset-1", reason: "timed out")
        )
        #expect(policy.isRetryable(error))
    }

    @Test func inferenceFailedIsRetryable() {
        let error = AppError.embeddingGenerationFailed(
            assetID: "asset-1",
            underlying: EmbeddingPipelineError.inferenceFailed(underlying: FakeUnderlyingError())
        )
        #expect(policy.isRetryable(error))
    }

    @Test func assetNotFoundIsNotRetryable() {
        let error = AppError.embeddingGenerationFailed(
            assetID: "asset-1",
            underlying: EmbeddingPipelineError.assetNotFound(localIdentifier: "asset-1")
        )
        #expect(!policy.isRetryable(error))
    }

    @Test func modelNotProvisionedIsNotRetryable() {
        let error = AppError.embeddingGenerationFailed(
            assetID: "asset-1",
            underlying: EmbeddingPipelineError.modelNotProvisioned(.image)
        )
        #expect(!policy.isRetryable(error))
    }

    @Test func dimensionMismatchIsNotRetryable() {
        let error = AppError.embeddingGenerationFailed(
            assetID: "asset-1",
            underlying: EmbeddingPipelineError.dimensionMismatch(expected: 512, actual: 384)
        )
        #expect(!policy.isRetryable(error))
    }

    @Test func underlyingErrorFromAnotherBoundaryIsNotRetryable() {
        // A non-EmbeddingPipelineError underlying (e.g. wrapping a raw
        // PhotoStore.upsertEmbedding failure) shouldn't be treated as
        // retryable just because the outer case matches.
        let error = AppError.embeddingGenerationFailed(assetID: "asset-1", underlying: FakeUnderlyingError())
        #expect(!policy.isRetryable(error))
    }

    @Test func errorsFromOtherBoundariesAreNotRetryable() {
        #expect(!policy.isRetryable(.photosFetchFailed(underlying: FakeUnderlyingError())))
        #expect(!policy.isRetryable(.llmTimeout))
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
