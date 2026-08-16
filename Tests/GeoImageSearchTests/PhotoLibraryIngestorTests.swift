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

    // Gap found in coverage audit: permission-denial's `progress?.fail(...)`
    // call was added by this diff but every existing denied-access test
    // calls run() without a progress reporter, so the optional-chain no-ops
    // and this line never actually executes under test.
    @Test @MainActor func deniedAccessWithProgressSetsFailedPhase() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let progress = SyncProgress()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .denied)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("a")])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        var thrownError: Error?
        do {
            _ = try await ingestor.run(progress: progress)
        } catch {
            thrownError = error
        }
        #expect(thrownError is AppError)
        #expect(progress.phase == .failed(AppError.photosPermissionDenied.logDescription))
    }

    // Gap found in coverage audit: the code comment on the dateRange filter
    // explicitly calls out that a creationDate-less asset "can't be
    // confirmed to belong" in a scoped window and is excluded — but no test
    // exercised a snapshot with a nil creationDate under an active scope.
    @Test func dateRangeScopeExcludesSnapshotsWithNilCreationDate() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let inRangeDate = Date(timeIntervalSince1970: 1_700_000_000)
        let undated = PhotoAssetSnapshot(
            localIdentifier: "undated",
            latitude: 48.8566, longitude: 2.3522,
            creationDate: nil, modificationDate: nil,
            isLivePhoto: false
        )
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("recent", date: inRangeDate), undated])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run(
            dateRange: Date(timeIntervalSince1970: 1_500_000_000)...Date(timeIntervalSince1970: 2_000_000_000)
        )

        #expect(result.upsertedCount == 1)
        let identifiers = try await query.allActiveIdentifiers()
        #expect(Set(identifiers.keys) == ["recent"])
    }

    // Found in pre-landing review (testing specialist): the fetch-failure
    // catch branch's progress?.fail(...) call was untested — every existing
    // fetch-failure test (fetchIsRetriedThenSucceeds) only covers the
    // eventual-success path, none exhaust every retry attempt with a
    // progress reporter attached.
    @Test @MainActor func fetchFailureExhaustingRetriesSetsFailedProgress() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let progress = SyncProgress()
        let fetcher = SerialFakeFetcher(results: [
            .failure(AppError.photosFetchFailed(underlying: TestError())),
            .failure(AppError.photosFetchFailed(underlying: TestError())),
            .failure(AppError.photosFetchFailed(underlying: TestError()))
        ])
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: fetcher,
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        var thrownError: Error?
        do {
            _ = try await ingestor.run(progress: progress)
        } catch {
            thrownError = error
        }
        #expect(thrownError is AppError)
        if case .failed = progress.phase {} else {
            Issue.record("expected failed phase, got \(progress.phase)")
        }
    }

    // Found in pre-landing review (testing specialist): a re-sync where
    // nothing changed (plan.toUpsert is empty) drives progress through
    // start(total: 0) — SyncProgressView's max(total, 1) guard implies this
    // is an expected real case, but no test asserted it reaches .finished
    // cleanly rather than getting stuck or reporting a bogus count.
    @Test @MainActor func progressWithNothingToUpsertReachesFinishedDirectly() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let unchangedDate = Date(timeIntervalSince1970: 1_000)
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "unchanged", updatedAt: unchangedDate)])
        let progress = SyncProgress()
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [.success([snapshot("unchanged", date: unchangedDate)])]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        let result = try await ingestor.run(progress: progress)

        #expect(result.upsertedCount == 0)
        #expect(progress.phase == .finished(result))
    }

    // Gap found in coverage audit (commit 91953e0): PhotoLibraryIngestor.run
    // now wraps query.allActiveIdentifiers(), store.upsert(), and
    // store.markDeleted() in do/catch blocks that call progress?.fail(...)
    // before rethrowing — completing the fail-on-every-throw contract across
    // all 4 throw paths. But every existing test drives store/query through
    // the real in-memory SQLite implementations, which never fail, so these
    // 3 new catch blocks (added specifically to make failure symmetric with
    // the permission/fetch paths) never actually executed under test.
    @Test(
        "storage/query failure during run sets failed progress and rethrows",
        arguments: IngestorFailurePoint.allCases
    )
    @MainActor
    func storageFailureDuringRunSetsFailedProgressAndRethrows(_ failurePoint: IngestorFailurePoint) async throws {
        let (realStore, realQuery) = try await TestDatabase.makeStoreAndQuery()
        // Only the markDeleted path needs a pre-existing stored asset that's
        // absent from the fresh fetch (full access, no dateRange scope) so
        // plan.idsToMarkDeleted is non-empty and markDeleted actually gets
        // called.
        if failurePoint == .markDeleted {
            try await realStore.upsert([PhotoAssetFixtures.makeAsset(id: "gone")])
        }
        let store = FailingPhotoStore(
            wrapping: realStore,
            failOnUpsert: failurePoint == .upsert,
            failOnMarkDeleted: failurePoint == .markDeleted
        )
        let query = FailingPhotoQuery(wrapping: realQuery, failOnActiveIdentifiers: failurePoint == .query)
        let progress = SyncProgress()
        // markDeleted needs an empty fetch (so "gone" isn't re-seen); the
        // other two paths need at least one asset flowing into upsert.
        let fetchedSnapshots = failurePoint == .markDeleted ? [] : [snapshot("a")]
        let ingestor = PhotoLibraryIngestor(
            store: store, query: query,
            permissionManager: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized)),
            fetcher: SerialFakeFetcher(results: [.success(fetchedSnapshots)]),
            geocoder: FakeReverseGeocoder(placeNamesByCoordinate: [:])
        )

        var thrownError: Error?
        do {
            _ = try await ingestor.run(progress: progress)
        } catch {
            thrownError = error
        }

        #expect(thrownError != nil)
        if case .failed(let message) = progress.phase {
            #expect(message == "Sync failed: \(TestError())")
        } else {
            Issue.record("expected failed phase, got \(progress.phase)")
        }
    }
}

private struct TestError: Error {}

enum IngestorFailurePoint: String, CaseIterable, Sendable, CustomStringConvertible {
    case query, upsert, markDeleted
    var description: String { rawValue }
}

// Delegates every read to the real in-memory query except
// allActiveIdentifiers(), which can be switched to throw — exercises
// PhotoLibraryIngestor.run's `query.allActiveIdentifiers()` catch block
// (added in 91953e0) without needing a full hand-written PhotoQuery mock.
private final class FailingPhotoQuery: PhotoQuery, @unchecked Sendable {
    private let wrapped: SQLitePhotoQuery
    private let failOnActiveIdentifiers: Bool

    init(wrapping wrapped: SQLitePhotoQuery, failOnActiveIdentifiers: Bool) {
        self.wrapped = wrapped
        self.failOnActiveIdentifiers = failOnActiveIdentifiers
    }

    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset] {
        try await wrapped.byLocation(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
    }

    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset] {
        try await wrapped.byDateRange(start: start, end: end)
    }

    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset] {
        try await wrapped.bySimilarity(embedding: embedding, limit: limit)
    }

    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster] {
        try await wrapped.clusterTrips(minStopDuration: minStopDuration, maxTravelGap: maxTravelGap)
    }

    func allActivePhotosWithLocation() async throws -> [PhotoAsset] {
        try await wrapped.allActivePhotosWithLocation()
    }

    func allActiveIdentifiers() async throws -> [String: StoredPhotoIdentity] {
        if failOnActiveIdentifiers { throw TestError() }
        return try await wrapped.allActiveIdentifiers()
    }
}

// Delegates to the real in-memory store except upsert()/markDeleted(), each
// independently switchable to throw — exercises PhotoLibraryIngestor.run's
// store.upsert() and store.markDeleted() catch blocks (added in 91953e0).
private final class FailingPhotoStore: PhotoStore, @unchecked Sendable {
    private let wrapped: SQLitePhotoStore
    private let failOnUpsert: Bool
    private let failOnMarkDeleted: Bool

    init(wrapping wrapped: SQLitePhotoStore, failOnUpsert: Bool, failOnMarkDeleted: Bool) {
        self.wrapped = wrapped
        self.failOnUpsert = failOnUpsert
        self.failOnMarkDeleted = failOnMarkDeleted
    }

    func upsert(_ assets: [PhotoAsset]) async throws {
        if failOnUpsert { throw TestError() }
        try await wrapped.upsert(assets)
    }

    func markDeleted(ids: [String]) async throws {
        if failOnMarkDeleted { throw TestError() }
        try await wrapped.markDeleted(ids: ids)
    }

    func upsertEmbedding(_ record: EmbeddingRecord) async throws {
        try await wrapped.upsertEmbedding(record)
    }
}
