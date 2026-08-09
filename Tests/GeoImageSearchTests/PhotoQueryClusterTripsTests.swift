import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQueryClusterTripsTests {
    private func makeStoreAndQuery() async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
    }

    private static let base: TimeInterval = 1_700_000_000
    private static let minStopDuration: TimeInterval = 1800 // 30 min
    private static let maxTravelGap: TimeInterval = 7200 // 2 hours

    private static func t(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: base + offset)
    }

    @Test func splitsIntoClustersDropsShortStopsAndExcludesNoGPS() async throws {
        let (store, query) = try await makeStoreAndQuery()

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
        #expect(clusterA.centroidLongitude == 10)
        #expect(clusterA.placeName == "CityA")
        #expect(clusterA.startDate == Self.t(0))
        #expect(clusterA.endDate == Self.t(3600))

        let clusterB = try #require(clusters.first { $0.assetIDs.contains("b1") })
        #expect(Set(clusterB.assetIDs) == ["b1", "b2", "b3"])
        #expect(clusterB.centroidLatitude == 20)
        #expect(clusterB.centroidLongitude == 20)
        #expect(clusterB.placeName == "CityB")
    }

    @Test func noPhotosProducesNoClusters() async throws {
        let (_, query) = try await makeStoreAndQuery()
        let clusters = try await query.clusterTrips(minStopDuration: Self.minStopDuration, maxTravelGap: Self.maxTravelGap)
        #expect(clusters.isEmpty)
    }
}
