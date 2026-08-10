import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQueryClusterTripsTests {
    private static let base: TimeInterval = 1_700_000_000
    private static let minStopDuration: TimeInterval = 1800 // 30 min
    private static let maxTravelGap: TimeInterval = 7200 // 2 hours

    private static func t(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: base + offset)
    }

    @Test func splitsIntoClustersDropsShortStopsAndExcludesNoGPS() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()

        // Cluster A: 3 photos within a 1-hour span at (10,10). Gap to next
        // segment exceeds maxTravelGap, so it becomes its own cluster.
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "a1", latitude: 10, longitude: 10, capturedAt: Self.t(0), placeName: "CityA"),
            PhotoAssetFixtures.makeAsset(id: "a2", latitude: 10, longitude: 10, capturedAt: Self.t(1800), placeName: "CityA"),
            PhotoAssetFixtures.makeAsset(id: "a3", latitude: 10, longitude: 10, capturedAt: Self.t(3600), placeName: nil)
        ])

        // Stray single photo, isolated by >maxTravelGap on both sides —
        // span is 0 (a single point), under minStopDuration, must be dropped.
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "stray", latitude: 15, longitude: 15, capturedAt: Self.t(3600 + 7201))
        ])

        // Cluster B: 3 photos spanning 1 hour at (20,20), far enough in time
        // from the stray photo to start a new cluster.
        let bStart: TimeInterval = 3600 + 7201 + 7201
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "b1", latitude: 20, longitude: 20, capturedAt: Self.t(bStart), placeName: "CityB"),
            PhotoAssetFixtures.makeAsset(id: "b2", latitude: 20, longitude: 20, capturedAt: Self.t(bStart + 1800), placeName: "CityB"),
            PhotoAssetFixtures.makeAsset(id: "b3", latitude: 20, longitude: 20, capturedAt: Self.t(bStart + 3600), placeName: "CityB")
        ])

        // Never enters clustering at all — excluded before the temporal walk
        // even begins, since allActivePhotosWithLocation drops it at the SQL level.
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil, capturedAt: Self.t(1000))
        ])

        let clusters = try await query.clusterTrips(minStopDuration: Self.minStopDuration, maxTravelGap: Self.maxTravelGap)

        #expect(clusters.count == 2)

        let allMemberIDs = clusters.flatMap(\.assetIDs)
        #expect(!allMemberIDs.contains("stray"))
        #expect(!allMemberIDs.contains("no-gps"))

        let clusterA = try #require(clusters.first { $0.assetIDs.contains("a1") })
        #expect(Set(clusterA.assetIDs) == ["a1", "a2", "a3"])
        #expect(clusterA.centroidLatitude == 10)
        // Circular mean round-trips through sin/cos/atan2, so it isn't
        // bit-exact for a value like 10 the way a plain arithmetic mean is.
        #expect(abs(clusterA.centroidLongitude - 10) < 1e-9)
        #expect(clusterA.placeName == "CityA")
        #expect(clusterA.startDate == Self.t(0))
        #expect(clusterA.endDate == Self.t(3600))

        let clusterB = try #require(clusters.first { $0.assetIDs.contains("b1") })
        #expect(Set(clusterB.assetIDs) == ["b1", "b2", "b3"])
        #expect(clusterB.centroidLatitude == 20)
        #expect(abs(clusterB.centroidLongitude - 20) < 1e-9)
        #expect(clusterB.placeName == "CityB")
    }

    @Test func noPhotosProducesNoClusters() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let clusters = try await query.clusterTrips(minStopDuration: Self.minStopDuration, maxTravelGap: Self.maxTravelGap)
        #expect(clusters.isEmpty)
    }

    // clusterTrips splits on `gap > maxTravelGap` (strict), so a gap exactly
    // equal to maxTravelGap must NOT split — this is the boundary a `>=`
    // typo would silently get wrong.
    @Test func gapExactlyEqualToMaxTravelGapDoesNotSplit() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "x1", capturedAt: Self.t(0)),
            PhotoAssetFixtures.makeAsset(id: "x2", capturedAt: Self.t(Self.maxTravelGap))
        ])

        let clusters = try await query.clusterTrips(minStopDuration: Self.minStopDuration, maxTravelGap: Self.maxTravelGap)

        #expect(clusters.count == 1)
        #expect(Set(clusters.first?.assetIDs ?? []) == ["x1", "x2"])
    }

    // Symmetric to gapExactlyEqualToMaxTravelGapDoesNotSplit: clusterTrips
    // keeps a cluster when `span >= minStopDuration` (inclusive) — a span
    // exactly equal to minStopDuration must survive rather than getting
    // dropped as a "short stop." This is the boundary a `>` typo (instead
    // of `>=`) would silently flip, and it's a different comparison in a
    // different direction than the maxTravelGap boundary test above.
    @Test func spanExactlyEqualToMinStopDurationIsKept() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "y1", capturedAt: Self.t(0)),
            PhotoAssetFixtures.makeAsset(id: "y2", capturedAt: Self.t(Self.minStopDuration))
        ])

        let clusters = try await query.clusterTrips(minStopDuration: Self.minStopDuration, maxTravelGap: Self.maxTravelGap)

        #expect(clusters.count == 1)
        #expect(Set(clusters.first?.assetIDs ?? []) == ["y1", "y2"])
    }

    // A plain arithmetic mean of +179.9 and -179.9 gives ~0 (Greenwich) —
    // circularMeanDegrees must place the centroid near ±180 (the dateline)
    // instead, since that's where the trip's photos actually are.
    @Test func centroidHandlesAntimeridianCrossingTrip() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "d1", latitude: 0, longitude: 179.9, capturedAt: Self.t(0)),
            PhotoAssetFixtures.makeAsset(id: "d2", latitude: 0, longitude: -179.9, capturedAt: Self.t(1800))
        ])

        let clusters = try await query.clusterTrips(minStopDuration: Self.minStopDuration, maxTravelGap: Self.maxTravelGap)

        let cluster = try #require(clusters.first)
        #expect(abs(cluster.centroidLongitude) > 170) // near ±180, not ~0
    }
}
