import CoreGraphics
// CoreML's async prediction API isn't Sendable-audited on this SDK yet
// (MLModel/MLFeatureProvider aren't marked Sendable despite Apple
// documenting MLModel as safe for concurrent prediction calls) —
// @preconcurrency suppresses the resulting false-positive diagnostics.
@preconcurrency import CoreML
import Foundation
import Vision

protocol ImageEmbedding: Sendable {
    func embed(cgImage: CGImage) async throws -> [Float]
}

// Wraps mobileclip_s2_image.mlpackage. MLModel isn't Sendable — owning it
// as actor-isolated state serializes CoreML inference, which matches how
// concurrent prediction(from:) calls on one instance behave anyway; thumbnail
// I/O runs concurrently outside this actor (see EmbeddingQueue).
actor ImageEmbedder: ImageEmbedding {
    private let model: MLModel

    init(modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
    }

    func embed(cgImage: CGImage) async throws -> [Float] {
        guard let constraint = model.modelDescription
            .inputDescriptionsByName[EmbeddingModelInfo.imageInputFeatureName]?.imageConstraint
        else {
            throw EmbeddingPipelineError.modelNotProvisioned(.image)
        }

        // Let CoreML resize/crop/convert to exactly what the graph expects
        // via its own declared constraint, instead of hand-building a
        // 256x256 CVPixelBuffer and guessing a pixel format. .centerCrop
        // matches standard CLIP preprocessing (resize-shorter-side + crop).
        // Preprocessing beyond that (1/255 scale) is baked into the graph —
        // no extra mean/std normalization here.
        let featureValue = try MLFeatureValue(
            cgImage: cgImage,
            constraint: constraint,
            options: [.cropAndScale: VNImageCropAndScaleOption.centerCrop.rawValue]
        )
        let input = try MLDictionaryFeatureProvider(
            dictionary: [EmbeddingModelInfo.imageInputFeatureName: featureValue]
        )

        let output = try await model.prediction(from: input)
        guard let raw = output.featureValue(for: EmbeddingModelInfo.outputFeatureName)?.multiArrayValue else {
            throw EmbeddingPipelineError.inferenceFailed(
                underlying: NSError(
                    domain: "ImageEmbedder",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Model output missing feature '\(EmbeddingModelInfo.outputFeatureName)'"]
                )
            )
        }
        let vector = raw.floatVector
        guard vector.count == EmbeddingModelInfo.embeddingDimension else {
            throw EmbeddingPipelineError.dimensionMismatch(expected: EmbeddingModelInfo.embeddingDimension, actual: vector.count)
        }
        return VectorMath.l2Normalized(vector)
    }
}
