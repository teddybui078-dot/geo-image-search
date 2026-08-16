// See ImageEmbedding.swift's matching comment on why this needs
// @preconcurrency.
@preconcurrency import CoreML
import Foundation

protocol TextEmbedding: Sendable {
    func embed(text: String) async throws -> [Float]
}

// Wraps mobileclip_s2_text.mlpackage — this is the type q-and-a-ai-agent's
// future semantic_search tool will call to embed a free-text query into
// the same space ImageEmbedder writes photo vectors into. Built and tested
// here, not wired into any agent tool (out of this worktree's scope).
actor TextEmbedder: TextEmbedding {
    private let model: MLModel
    private let tokenizer: CLIPTokenizer

    init(modelURL: URL, tokenizer: CLIPTokenizer, configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        model = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.tokenizer = tokenizer
    }

    func embed(text: String) async throws -> [Float] {
        // encode(_:contextLength:) already returns exactly contextLength
        // ids, padded/truncated — no manual pad/truncate step needed here.
        let tokenIDs = tokenizer.encode(text, contextLength: EmbeddingModelInfo.contextLength)

        let multiArray = try MLMultiArray(
            shape: [1, NSNumber(value: EmbeddingModelInfo.contextLength)],
            dataType: .int32
        )
        for (index, id) in tokenIDs.enumerated() {
            multiArray[index] = NSNumber(value: id)
        }

        let input = try MLDictionaryFeatureProvider(
            dictionary: [EmbeddingModelInfo.textInputFeatureName: MLFeatureValue(multiArray: multiArray)]
        )

        let output = try await model.prediction(from: input)
        guard let raw = output.featureValue(for: EmbeddingModelInfo.outputFeatureName)?.multiArrayValue else {
            throw EmbeddingPipelineError.inferenceFailed(
                underlying: NSError(
                    domain: "TextEmbedder",
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
