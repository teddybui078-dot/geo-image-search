import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQueryBasicTests {
    private func makeStoreAndQuery() async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
    }

    @Test func byDateRangeIncludesNoGPSPhotos() async throws {
        let (store, query) = try await makeStoreAndQuery()
        let inRange = Date(timeIntervalSince1970: 1_700_000_500)
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil, capturedAt: inRange)
        ])

        let results = try await query.byDateRange(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_001_000)
        )

        #expect(results.map(\.id) == ["no-gps"])
    }

    @Test func byDateRangeExcludesOutOfRangeAndDeleted() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "before", capturedAt: Date(timeIntervalSince1970: 1_699_000_000)),
            PhotoAssetFixtures.makeAsset(id: "in-range", capturedAt: Date(timeIntervalSince1970: 1_700_000_500)),
            PhotoAssetFixtures.makeAsset(id: "after", capturedAt: Date(timeIntervalSince1970: 1_701_000_000)),
            PhotoAssetFixtures.makeAsset(id: "deleted", capturedAt: Date(timeIntervalSince1970: 1_700_000_600))
        ])
        try await store.markDeleted(ids: ["deleted"])

        let results = try await query.byDateRange(
            start: Date(timeIntervalSince1970: 1_700_000_000),
            end: Date(timeIntervalSince1970: 1_700_001_000)
        )

        #expect(results.map(\.id) == ["in-range"])
    }

    @Test func allActivePhotosWithLocationExcludesNoGPSAndDeleted() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "with-gps"),
            PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil),
            PhotoAssetFixtures.makeAsset(id: "deleted-with-gps")
        ])
        try await store.markDeleted(ids: ["deleted-with-gps"])

        let results = try await query.allActivePhotosWithLocation()

        #expect(results.map(\.id) == ["with-gps"])
    }
}
