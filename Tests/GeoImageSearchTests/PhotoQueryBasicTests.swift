import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoQueryBasicTests {
    @Test func byDateRangeIncludesNoGPSPhotos() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
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
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
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
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "with-gps"),
            PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil),
            PhotoAssetFixtures.makeAsset(id: "deleted-with-gps")
        ])
        try await store.markDeleted(ids: ["deleted-with-gps"])

        let results = try await query.allActivePhotosWithLocation()

        #expect(results.map(\.id) == ["with-gps"])
    }

    // Int64(Double) traps on NaN or out-of-Int64-range values — a malformed
    // capturedAt (corrupted upstream metadata, not just contrived input)
    // must not crash the process on write or read.
    @Test func nonFiniteDatesDoNotCrash() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "nan-date", capturedAt: Date(timeIntervalSince1970: .nan)),
            PhotoAssetFixtures.makeAsset(id: "infinite-date", capturedAt: Date(timeIntervalSince1970: .infinity))
        ])

        let results = try await query.byDateRange(
            start: Date(timeIntervalSince1970: -1e30),
            end: Date(timeIntervalSince1970: 1e30)
        )

        #expect(results.count == 2)
    }

    @Test func allActiveIdentifiersIncludesNoGPSAndExcludesDeleted() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_123)
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "with-gps", updatedAt: updatedAt),
            PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil, updatedAt: updatedAt),
            PhotoAssetFixtures.makeAsset(id: "deleted")
        ])
        try await store.markDeleted(ids: ["deleted"])

        let identifiers = try await query.allActiveIdentifiers()

        #expect(Set(identifiers.keys) == ["with-gps", "no-gps"])
        #expect(identifiers["with-gps"] == updatedAt)
        #expect(identifiers["no-gps"] == updatedAt)
    }

    // nonFiniteDatesDoNotCrash above proves NaN/+infinity don't crash the
    // process end-to-end through the DB, but never asserts the actual
    // clamped value and never exercises -infinity at all (the Int64.min
    // branch). unixSecondsClamped is a pure Date extension — assert all
    // three clamp directions directly, no DB needed.
    @Test func unixSecondsClampedHandlesEveryNonFiniteDirection() {
        #expect(Date(timeIntervalSince1970: .nan).unixSecondsClamped == 0)
        #expect(Date(timeIntervalSince1970: .infinity).unixSecondsClamped == .max)
        #expect(Date(timeIntervalSince1970: -.infinity).unixSecondsClamped == .min)
    }
}
