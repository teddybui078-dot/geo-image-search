import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQueryLocationTests {
    @Test func returnsNearbyPhotoWithinRadius() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "near", latitude: 0.05, longitude: 0.05)])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.map(\.id) == ["near"])
    }

    @Test func excludesFarPhotoOutsideRadius() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "far", latitude: 5, longitude: 5)])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }

    @Test func excludesNoGPSPhoto() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil)])

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }

    @Test func excludesDeletedPhotoEvenWhenNearby() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
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
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "corner", latitude: 0.7, longitude: 0.7)])

        let straightLineDistance = GeoMath.haversineDistanceKm(lat1: 0, lon1: 0, lat2: 0.7, lon2: 0.7)
        #expect(straightLineDistance > 100) // sanity check on the fixture itself

        let results = try await query.byLocation(latitude: 0, longitude: 0, radiusKm: 100)

        #expect(results.isEmpty)
    }

    // radiusKm: 0 collapses both the R-Tree bbox and the haversine cutoff to
    // a single point — only an exact-coordinate match should survive.
    @Test func zeroRadiusOnlyMatchesExactCoordinates() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "exact", latitude: 10, longitude: 10),
            PhotoAssetFixtures.makeAsset(id: "close-but-not-exact", latitude: 10.001, longitude: 10)
        ])

        let results = try await query.byLocation(latitude: 10, longitude: 10, radiusKm: 0)

        #expect(results.map(\.id) == ["exact"])
    }

    // Regression test: SQLite's R-Tree module stores coordinates as 32-bit
    // floats and rounds min down / max up (expands stored boxes outward).
    // A containment-style prefilter query breaks against that expansion —
    // verified empirically that an exact self-query for a realistic-
    // precision GPS coordinate (unlike round numbers like 10, 10, which are
    // exactly representable in float32 and don't exercise this) returned
    // zero matches before the query was switched to an overlap predicate.
    @Test func realisticPrecisionCoordinatesAreNotExcludedByRTreeRounding() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let lat = 37.774929239481
        let lon = -122.419415749283
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "precise", latitude: lat, longitude: lon)])

        let results = try await query.byLocation(latitude: lat, longitude: lon, radiusKm: 1)

        #expect(results.map(\.id) == ["precise"])
    }

    // A single [minLon, maxLon] range can't express a box that wraps across
    // ±180° — without splitting it into two ranges, a photo just across the
    // antimeridian from the query point is silently dropped even though
    // it's well within radiusKm in a straight line.
    @Test func byLocationHandlesAntimeridianCrossing() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        // Query point at 179.9°E; photo at -179.9° (i.e. 179.9°W) — about
        // 22km apart going the short way across the date line, but ~40,000km
        // apart if longitude were compared without wrapping.
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "across-dateline", latitude: 0, longitude: -179.9)])

        let straightLineDistance = GeoMath.haversineDistanceKm(lat1: 0, lon1: 179.9, lat2: 0, lon2: -179.9)
        #expect(straightLineDistance < 50) // sanity check: genuinely close via the short way around

        let results = try await query.byLocation(latitude: 0, longitude: 179.9, radiusKm: 50)

        #expect(results.map(\.id) == ["across-dateline"])
    }
}
