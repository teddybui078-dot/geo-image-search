import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQueryLocationTests {
    private func makeStoreAndQuery() async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
    }

    @Test func returnsNearbyPhotoWithinRadius() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "near", latitude: 0.05, longitude: 0.05)])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.map(\.id) == ["near"])
    }

    @Test func excludesFarPhotoOutsideRadius() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "far", latitude: 5, longitude: 5)])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }

    @Test func excludesNoGPSPhoto() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil)])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }

    @Test func excludesDeletedPhotoEvenWhenNearby() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "deleted-near", latitude: 0.05, longitude: 0.05)])
        try await store.markDeleted(ids: ["deleted-near"])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }

    // Proves the two-phase filter: a point placed diagonally inside the
    // R-Tree's square bounding box, but outside the true circular radius
    // (a circle inscribed in a square always leaves the corners uncovered).
    // radiusKm=100 => box half-width ~0.898deg on each axis; this point
    // sits at (0.7, 0.7), inside the box but ~110km away in a straight
    // line — outside the 100km circle.
    @Test func excludesBoxCornerPointOutsideTrueCircle() async throws {
        let (store, query) = try await makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "corner", latitude: 0.7, longitude: 0.7)])

        let straightLineDistance = GeoMath.haversineDistanceKm(lat1: 0, lon1: 0, lat2: 0.7, lon2: 0.7)
        #expect(straightLineDistance > 100) // sanity check on the fixture itself

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }
}
