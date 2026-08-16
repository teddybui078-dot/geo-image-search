import Testing
@testable import GeoImageSearch

@Suite struct VectorMathTests {
    @Test func l2NormalizedProducesUnitVector() {
        let normalized = VectorMath.l2Normalized([3, 4])
        #expect(normalized[0].isApproximatelyEqual(to: 0.6))
        #expect(normalized[1].isApproximatelyEqual(to: 0.8))
    }

    @Test func l2NormalizedOfZeroVectorReturnsInputUnchanged() {
        let zero: [Float] = [0, 0, 0]
        #expect(VectorMath.l2Normalized(zero) == zero)
    }

    @Test func cosineSimilarityOfIdenticalVectorsIsOne() {
        let vector: [Float] = [0.6, 0.8]
        #expect(VectorMath.cosineSimilarity(vector, vector).isApproximatelyEqual(to: 1.0))
    }

    @Test func cosineSimilarityOfOrthogonalVectorsIsZero() {
        #expect(VectorMath.cosineSimilarity([1, 0], [0, 1]).isApproximatelyEqual(to: 0.0))
    }

    @Test func cosineSimilarityOfOppositeVectorsIsNegativeOne() {
        #expect(VectorMath.cosineSimilarity([1, 0], [-1, 0]).isApproximatelyEqual(to: -1.0))
    }

    @Test func cosineSimilarityAgainstZeroVectorIsZeroNotNaN() {
        #expect(VectorMath.cosineSimilarity([1, 0], [0, 0]) == 0)
    }
}

private extension Float {
    func isApproximatelyEqual(to other: Float, tolerance: Float = 0.0001) -> Bool {
        abs(self - other) < tolerance
    }
}
