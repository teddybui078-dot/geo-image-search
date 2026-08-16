import Foundation

// The underlying: payload wrapped inside AppError.embeddingGenerationFailed
// (see CONTRACT.md) — distinguishing these cases is what lets
// EmbeddingRetryPolicy decide retryability precisely instead of retrying
// every failure.
enum EmbeddingPipelineError: Error, Sendable {
    case modelNotProvisioned(EmbeddingModelAsset)
    case assetNotFound(localIdentifier: String)
    // A String, not PHImageManager's [AnyHashable: Any] info dict — that
    // dict isn't Sendable-safe to carry across the continuation boundary
    // PHPhotoThumbnailFetcher resumes from.
    case thumbnailUnavailable(assetLocalIdentifier: String, reason: String)
    case inferenceFailed(underlying: Error)
    case dimensionMismatch(expected: Int, actual: Int)
}
