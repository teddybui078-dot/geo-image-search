import CoreML
import Foundation

extension MLMultiArray {
    // Both MobileCLIP-S2 towers output a contiguous [1,512] FP32
    // MLMultiArray — a straight reinterpret of the backing buffer is safe
    // and avoids a slow per-element NSNumber subscript loop.
    var floatVector: [Float] {
        guard dataType == .float32 else {
            return (0..<count).map { Float(truncating: self[$0]) }
        }
        let pointer = dataPointer.bindMemory(to: Float.self, capacity: count)
        return Array(UnsafeBufferPointer(start: pointer, count: count))
    }
}

// Neither MobileCLIP-S2 tower L2-normalizes its output in-graph — callers
// must normalize before persisting/comparing, or sqlite-vec's cosine
// ranking (and this file's own cosineSimilarity) is wrong.
enum VectorMath {
    static func l2Normalized(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitude > 0 else { return vector }
        return vector.map { $0 / magnitude }
    }

    // Assumes equal-length, already-normalized inputs are the common case
    // (both embedders normalize before returning) but doesn't require it —
    // this is a plain dot-product-over-magnitudes cosine, safe either way.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "cosineSimilarity requires equal-length vectors")
        var dot: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        let denominator = sqrt(magnitudeA) * sqrt(magnitudeB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }
}
