import Foundation

// CONTRACT.md — locked write interface. Implemented by database-structure
// (SQLitePhotoStore); called by photo-icloud-extraction and embedding-pipeline.
protocol PhotoStore {
    func upsert(_ assets: [PhotoAsset]) async throws
    func markDeleted(ids: [String]) async throws
    func upsertEmbedding(_ record: EmbeddingRecord) async throws
}
