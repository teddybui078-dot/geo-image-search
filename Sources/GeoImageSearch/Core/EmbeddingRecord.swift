import Foundation

// CONTRACT.md — locked shape, shared across every feature worktree.
// vector's dimension depends on embedding-pipeline's CoreML model choice
// (TODOS.md item 5, not yet decided) — never assume a fixed length here.
struct EmbeddingRecord: Codable, Sendable {
    let assetID: String         // PhotoAsset.id
    let vector: [Float]         // dimension TBD
    let modelVersion: String    // e.g. "mobileclip-s0-v1" — lets you re-embed if the model changes
    let generatedAt: Date
}
