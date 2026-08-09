import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQuerySimilarityTests {
    private func makeStoreAndQuery() async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
    }

    private func embed(_ store: SQLitePhotoStore, id: String, vector: [Float]) async throws {
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: id, vector: vector, modelVersion: "test-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
    }

    @Test func wrongDimensionQueryThrows() async throws {
        let (_, query) = try await makeStoreAndQuery()
        await #expect(throws: SQLiteError.self) {
            _ = try await query.bySimilarity(embedding: [1, 2, 3], limit: 5)
        }
    }

    @Test func returnsResultsInDistanceOrder() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "closest"),
            PhotoAssetFixtures.makeAsset(id: "mid"),
            PhotoAssetFixtures.makeAsset(id: "far")
        ])
        try await embed(store, id: "closest", vector: [1, 0, 0, 0])
        try await embed(store, id: "mid", vector: [2, 0, 0, 0])
        try await embed(store, id: "far", vector: [10, 0, 0, 0])

        let results = try await query.bySimilarity(embedding: [1, 0, 0, 0], limit: 3)

        #expect(results.map(\.id) == ["closest", "mid", "far"])
    }

    @Test func limitTruncatesResults() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "closest"),
            PhotoAssetFixtures.makeAsset(id: "mid"),
            PhotoAssetFixtures.makeAsset(id: "far")
        ])
        try await embed(store, id: "closest", vector: [1, 0, 0, 0])
        try await embed(store, id: "mid", vector: [2, 0, 0, 0])
        try await embed(store, id: "far", vector: [10, 0, 0, 0])

        let results = try await query.bySimilarity(embedding: [1, 0, 0, 0], limit: 2)

        #expect(results.map(\.id) == ["closest", "mid"])
    }

    // Proves the overfetch-then-filter design: the objectively closest
    // match is soft-deleted, so the next-best active match should surface
    // in its place rather than the result silently shrinking below limit.
    @Test func softDeletedNearestMatchIsExcludedAndNextBestSurfaces() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "closest-but-deleted"),
            PhotoAssetFixtures.makeAsset(id: "next-best")
        ])
        try await embed(store, id: "closest-but-deleted", vector: [1, 0, 0, 0])
        try await embed(store, id: "next-best", vector: [2, 0, 0, 0])
        try await store.markDeleted(ids: ["closest-but-deleted"])

        let results = try await query.bySimilarity(embedding: [1, 0, 0, 0], limit: 1)

        #expect(results.map(\.id) == ["next-best"])
    }
}
