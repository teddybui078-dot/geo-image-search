import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQuerySimilarityTests {
    private func embed(_ store: SQLitePhotoStore, id: String, vector: [Float]) async throws {
        try await store.upsertEmbedding(EmbeddingRecord(
            assetID: id, vector: vector, modelVersion: "test-v1",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
    }

    @Test func wrongDimensionQueryThrows() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        await #expect(throws: SQLiteError.self) {
            _ = try await query.bySimilarity(embedding: [1, 2, 3], limit: 5)
        }
    }

    // SQLite treats a negative LIMIT as "unlimited" — without a guard, a
    // non-positive `limit` would silently return every active embedded
    // photo instead of an empty result.
    @Test func nonPositiveLimitReturnsEmptyRatherThanUnbounded() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "a"),
            PhotoAssetFixtures.makeAsset(id: "b")
        ])
        try await embed(store, id: "a", vector: [1, 0, 0, 0])
        try await embed(store, id: "b", vector: [2, 0, 0, 0])

        let zeroResults = try await query.bySimilarity(embedding: [1, 0, 0, 0], limit: 0)
        let negativeResults = try await query.bySimilarity(embedding: [1, 0, 0, 0], limit: -1)

        #expect(zeroResults.isEmpty)
        #expect(negativeResults.isEmpty)
    }

    // `limit * 4` traps on integer overflow for a large enough `limit`
    // (Swift's default Int arithmetic crashes the process on overflow) —
    // this must not crash, and should behave like any other large limit.
    @Test func veryLargeLimitDoesNotCrash() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a")])
        try await embed(store, id: "a", vector: [1, 0, 0, 0])

        let results = try await query.bySimilarity(embedding: [1, 0, 0, 0], limit: Int.max)

        #expect(results.map(\.id) == ["a"])
    }

    // The overfetch window must never be smaller than the caller's own
    // limit — a flat 200-row cap would truncate a request for 250 active
    // matches down to 200 even with zero soft-deleted rows in the way.
    @Test func limitAbove200IsNotTruncatedByOverfetchCap() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let assets = (0..<205).map { PhotoAssetFixtures.makeAsset(id: "p\($0)") }
        try await store.upsert(assets)
        for (index, asset) in assets.enumerated() {
            try await embed(store, id: asset.id, vector: [Float(index), 0, 0, 0])
        }

        let results = try await query.bySimilarity(embedding: [0, 0, 0, 0], limit: 205)

        #expect(results.count == 205)
    }

    // Regression test for a bug introduced while fixing the flat-200-cap
    // truncation bug: for limit in [200, 4095], overfetchK collapsed to
    // exactly `limit` (zero deletion buffer), silently contradicting the
    // overfetch design's own purpose. Seeds 50 soft-deleted photos as the
    // objectively nearest matches — with zero buffer, they'd occupy the
    // entire overfetch window and leave the active results short of limit.
    @Test func limitInZeroBufferRangeStillGetsFullBufferAgainstDeletedRows() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()

        let deleted = (0..<50).map { PhotoAssetFixtures.makeAsset(id: "deleted\($0)") }
        try await store.upsert(deleted)
        for asset in deleted {
            try await embed(store, id: asset.id, vector: [0, 0, 0, 0]) // distance 0 — objectively nearest
        }
        try await store.markDeleted(ids: deleted.map(\.id))

        let active = (0..<200).map { PhotoAssetFixtures.makeAsset(id: "active\($0)") }
        try await store.upsert(active)
        for (index, asset) in active.enumerated() {
            try await embed(store, id: asset.id, vector: [Float(index + 1), 0, 0, 0])
        }

        let results = try await query.bySimilarity(embedding: [0, 0, 0, 0], limit: 200)

        #expect(results.count == 200)
    }

    @Test func returnsResultsInDistanceOrder() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
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
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
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
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
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
