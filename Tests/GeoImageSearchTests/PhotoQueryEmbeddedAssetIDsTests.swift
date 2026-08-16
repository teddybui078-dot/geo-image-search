import Foundation
import Testing
@testable import GeoImageSearch

@Suite struct PhotoQueryEmbeddedAssetIDsTests {
    @Test func returnsAssetsEmbeddedAtTheGivenModelVersion() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "a"),
            PhotoAssetFixtures.makeAsset(id: "b")
        ])
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a", vector: [1, 2, 3, 4], modelVersion: "mobileclip-s2-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let embedded = try await query.embeddedAssetIDs(modelVersion: "mobileclip-s2-v1")

        #expect(embedded == ["a"])
    }

    @Test func differentModelVersionIsFilteredOut() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a", vector: [1, 2, 3, 4], modelVersion: "mobileclip-s0-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))

        let embedded = try await query.embeddedAssetIDs(modelVersion: "mobileclip-s2-v1")

        #expect(embedded.isEmpty)
    }

    @Test func noEmbeddingsReturnsEmptySet() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])

        let embedded = try await query.embeddedAssetIDs(modelVersion: "mobileclip-s2-v1")

        #expect(embedded.isEmpty)
    }

    @Test func reembeddingAtNewModelVersionUpdatesMembership() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a", vector: [1, 2, 3, 4], modelVersion: "mobileclip-s0-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: "a", vector: [5, 6, 7, 8], modelVersion: "mobileclip-s2-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))

        #expect(try await query.embeddedAssetIDs(modelVersion: "mobileclip-s0-v1").isEmpty)
        #expect(try await query.embeddedAssetIDs(modelVersion: "mobileclip-s2-v1") == ["a"])
    }
}
