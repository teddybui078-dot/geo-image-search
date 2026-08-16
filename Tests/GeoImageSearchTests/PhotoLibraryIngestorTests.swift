import Photos
import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoLibraryIngestorTests {
    private func snapshot(
        _ id: String,
        latitude: Double? = 48.8566,
        longitude: Double? = 2.3522,
        date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> PhotoAssetSnapshot {
        PhotoAssetSnapshot(
            localIdentifier: id,
            latitude: latitude, longitude: longitude,
            creationDate: date, modificationDate: date,
            isLivePhoto: false
        )
    }

    @Test func deniedAccessThrowsAndWritesNothing() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let reporter = SpyErrorReporter()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .denied)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("a")])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:]),
            errorReporter: reporter
        )

        await #expect(throws: AppError.self) {
            try await ingestor.run()
        }
        #expect(reporter.reported.map(\.error.logDescription) == [AppError.photosPermissionDenied.logDescription])
        #expect(try await query.allActiveIdentifiers().isEmpty)
    }

    @Test func firstRunUpsertsEveryAssetAndResolvesPlaceNames() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("a"), snapshot("b", latitude: nil, longitude: nil)])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [GeoBucket.key(latitude: 48.8566, longitude: 2.3522): "Paris, France"])
        )

        let result = try await ingestor.run()

        #expect(result.upsertedCount == 2)
        #expect(result.deletedCount == 0)
        #expect(result.totalLibraryAssets == 2)
        #expect(result.gpsCoverage.assetsWithGPS == 1)
        #expect(result.isLimitedAccess == false)

        let stored = try await query.byDateRange(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 2_000_000_000)
        )
        #expect(stored.first(where: { $0.id == "a" })?.placeName == "Paris, France")
        #expect(stored.first(where: { $0.id == "b" })?.placeName == nil)
    }

    @Test func relaunchOnlyTouchesNewChangedAndDeletedAssets() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let unchangedDate = Date(timeIntervalSince1970: 1_000)
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "unchanged", updatedAt: unchangedDate),
            PhotoAssetFixtures.makeAsset(id: "gone", updatedAt: unchangedDate)
        ])

        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [
                .success([
                    snapshot("unchanged", date: unchangedDate),
                    snapshot("new", date: Date(timeIntervalSince1970: 2_000))
                ])
            ]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run()

        #expect(result.upsertedCount == 1) // only "new" — "unchanged" is skipped
        #expect(result.deletedCount == 1)  // "gone" is no longer in the library

        let identifiers = try await query.allActiveIdentifiers()
        #expect(Set(identifiers.keys) == ["unchanged", "new"])
    }

    @Test func limitedAccessFlagPropagatesToResult() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .limited)),
            fetcher: SerialFakeFetcher(results: [.success([])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run()
        #expect(result.isLimitedAccess)
    }

    // Regression: under "Selected Photos" limited access, PHAsset fetch
    // only returns the visible subset — a stored photo absent from that
    // fetch might just be outside the current selection, not actually
    // deleted. A previous version of this code soft-deleted it anyway.
    @Test func limitedAccessDoesNotDeletePhotosOutsideVisibleSubset() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "outside-selection")])

        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .limited)),
            // The limited fetch doesn't include "outside-selection" at all.
            fetcher: SerialFakeFetcher(results: [.success([snapshot("visible")])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run()

        #expect(result.deletedCount == 0)
        let identifiers = try await query.allActiveIdentifiers()
        #expect(identifiers.keys.contains("outside-selection"))
    }

    // Regression: a re-upserted asset (modificationDate changed) whose
    // geocode call fails must keep its previously-resolved place name, not
    // have it overwritten with nil.
    @Test func geocodeFailureOnReupsertPreservesExistingPlaceName() async throws {
        struct FailingGeocoder: ReverseGeocoding {
            func placeName(latitude: Double, longitude: Double) async throws -> String? {
                throw AppError.geocodingFailed(underlying: TestError())
            }
        }
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let originalDate = Date(timeIntervalSince1970: 1_000)
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "a", updatedAt: originalDate, placeName: "Paris, France")
        ])

        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            // Same id, but a later modificationDate — SyncPlanner re-upserts it.
            fetcher: SerialFakeFetcher(results: [.success([snapshot("a", date: Date(timeIntervalSince1970: 2_000))])]),
            geocoder: FailingGeocoder()
        )

        let result = try await ingestor.run()
        #expect(result.upsertedCount == 1)

        let stored = try await query.byDateRange(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3_000)
        )
        #expect(stored.first(where: { $0.id == "a" })?.placeName == "Paris, France")
    }

    @Test func fetchIsRetriedThenSucceeds() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let fetcher = SerialFakeFetcher(results: [
            .failure(AppError.photosFetchFailed(underlying: TestError())),
            .success([snapshot("a")])
        ])
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: fetcher,
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run()

        #expect(result.upsertedCount == 1)
        #expect(fetcher.callCount == 2)
    }

    @Test func geocodingFailureDegradesToNilPlaceNameRatherThanAborting() async throws {
        struct FailingGeocoder: ReverseGeocoding {
            func placeName(latitude: Double, longitude: Double) async throws -> String? {
                throw AppError.geocodingFailed(underlying: TestError())
            }
        }
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let reporter = SpyErrorReporter()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("a")])]),
            geocoder: FailingGeocoder(),
            errorReporter: reporter
        )

        let result = try await ingestor.run()

        #expect(result.upsertedCount == 1)
        #expect(reporter.reported.contains { $0.context == "PhotoLibraryIngestor.resolvedPlaceName" })
    }

    @Test func dateRangeScopeExcludesAssetsOutsideRange() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let inRange = Date(timeIntervalSince1970: 1_700_000_000)
        let outOfRange = Date(timeIntervalSince1970: 1_000_000_000)
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [
                .success([snapshot("recent", date: inRange), snapshot("old", date: outOfRange)])
            ]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run(
            dateRange: Date(timeIntervalSince1970: 1_500_000_000)...Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(result.upsertedCount == 1)
        let identifiers = try await query.allActiveIdentifiers()
        #expect(Set(identifiers.keys) == ["recent"])
    }

    // Regression: narrowing the date range must never soft-delete photos
    // previously synced from outside the new, narrower window — the fresh,
    // scoped enumeration not containing them isn't evidence they're gone
    // from the library, same reasoning as the limited-access guard above.
    @Test func dateRangeScopeSkipsDeletionsEvenWhenAssetsAreMissing() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "outside-range")])

        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            // The scoped fetch doesn't include "outside-range" at all.
            fetcher: SerialFakeFetcher(results: [.success([snapshot("in-range")])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run(
            dateRange: Date(timeIntervalSince1970: 0)...Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(result.deletedCount == 0)
        let identifiers = try await query.allActiveIdentifiers()
        #expect(identifiers.keys.contains("outside-range"))
    }

    @Test @MainActor func progressReporterReceivesUpdatesDuringRun() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let progress = SyncProgress()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("a"), snapshot("b")])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run(progress: progress)

        #expect(progress.phase == .finished(result))
    }
}

private struct TestError: Error {}
