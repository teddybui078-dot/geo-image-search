import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoStoreEmbeddingTests {
    @Test func correctDimensionVectorSucceeds() async throws {
        let (store, _) = try await TestDatabase.makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])

        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a",
            vector: [1, 2, 3, 4],
            modelVersion: "mobileclip-s0-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
    }

    @Test func wrongDimensionVectorThrows() async throws {
        let (store, _) = try await TestDatabase.makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])

        await #expect(throws: SQLiteError.self) {
            try await store.upsertEmbedding(EmbeddingRecord(
                assetID: "a",
                vector: [1, 2, 3],
                modelVersion: "mobileclip-s0-v1",
                generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ))
        }
    }

    @Test func reupsertingSameAssetIDReplacesRatherThanDuplicates() async throws {
        let (store, connection) = try await TestDatabase.makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])

        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a", vector: [1, 2, 3, 4], modelVersion: "v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a", vector: [5, 6, 7, 8], modelVersion: "v2",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))

        let embeddingCount = try await connection.query(
            "SELECT COUNT(*) FROM photo_embeddings", map: { $0.columnInt64(0) }
        ).first
        #expect(embeddingCount == 1)

        let metaCount = try await connection.query(
            "SELECT COUNT(*) FROM photo_embedding_meta", map: { $0.columnInt64(0) }
        ).first
        #expect(metaCount == 1)

        let modelVersion = try await connection.query(
            "SELECT model_version FROM photo_embedding_meta WHERE asset_id = ?",
            bind: { try $0.bind("a", at: 1) },
            map: { $0.columnText(0) }
        ).first
        #expect(modelVersion == "v2")
    }
}
