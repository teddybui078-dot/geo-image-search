import Foundation

struct IngestResult: Sendable, Equatable {
    let isLimitedAccess: Bool
    let totalLibraryAssets: Int
    let gpsCoverage: GPSCoverageReport
    let upsertedCount: Int
    let deletedCount: Int
}

// Next Steps 1/1a/2 orchestrator: permission -> enumerate -> diff (SyncPlanner)
// -> geocode -> write (PhotoStore). One call is one relaunch-safe sync pass;
// see CONTRACT.md's "Relaunch sync strategy" for why there's no separate
// first-launch code path.
struct PhotoLibraryIngestor {
    private let permissionManager: any PhotosAuthorizing
    private let fetcher: any PhotoLibraryFetching
    private let geocoder: any ReverseGeocoding
    private let store: any PhotoStore
    private let query: any PhotoQuery
    private let errorReporter: any ErrorReporting
    private let batchSize: Int

    init(
        store: any PhotoStore,
        query: any PhotoQuery,
        permissionManager: any PhotosAuthorizing = PhotosPermissionManager(),
        fetcher: any PhotoLibraryFetching = PHPhotoLibraryFetcher(),
        geocoder: any ReverseGeocoding = ReverseGeocoder(),
        errorReporter: any ErrorReporting = ErrorReporter(),
        batchSize: Int = 200
    ) {
        // stride(from:to:by:) traps on a zero/negative step — fail fast
        // here with a clear message instead of a confusing crash deep in
        // run(). Found in review (Codex).
        precondition(batchSize > 0, "batchSize must be positive")
        self.store = store
        self.query = query
        self.permissionManager = permissionManager
        self.fetcher = fetcher
        self.geocoder = geocoder
        self.errorReporter = errorReporter
        self.batchSize = batchSize
    }

    // Throws (rather than folding failure into IngestResult) for permission
    // denial, an exhausted Photos fetch, or a genuine PhotoStore/PhotoQuery
    // failure — all three mean this pass produced no usable result, so the
    // caller should see that as an error, not a zero-count "success".
    // Per-asset geocoding failures are the one place this degrades instead
    // of aborting: see resolvedPlaceName below.
    func run() async throws -> IngestResult {
        let access = await permissionManager.requestAccess()
        guard access.isGranted else {
            errorReporter.report(.photosPermissionDenied, context: "PhotoLibraryIngestor.run")
            throw AppError.photosPermissionDenied
        }

        let fetcher = self.fetcher // avoid capturing non-Sendable `self` in the @Sendable closure below
        let snapshots: [PhotoAssetSnapshot]
        do {
            snapshots = try await RetryExecutor.run(policy: PhotosRetryPolicy()) {
                try fetcher.fetchAllPhotoAssetSnapshots()
            }
        } catch {
            let appError = (error as? AppError) ?? .photosFetchFailed(underlying: error)
            errorReporter.report(appError, context: "PhotoLibraryIngestor.run.fetch")
            throw appError
        }

        let coverage = GPSCoverageReport.measure(snapshots)
        // PhotoStore/PhotoQuery failures propagate untouched — they're
        // SQLiteError, not AppError; CONTRACT.md's AppError cases cover the
        // Photos/CLGeocoder/LLM/embedding/webview boundaries, not storage.
        let storedIdentifiers = try await query.allActiveIdentifiers()

        let now = Date()
        let plan = SyncPlanner.plan(librarySnapshots: snapshots, storedIdentifiers: storedIdentifiers)

        var upsertedCount = 0
        for start in stride(from: 0, to: plan.toUpsert.count, by: batchSize) {
            let end = min(start + batchSize, plan.toUpsert.count)
            var assets: [PhotoAsset] = []
            assets.reserveCapacity(end - start)
            for snapshot in plan.toUpsert[start..<end] {
                let existingPlaceName = storedIdentifiers[snapshot.localIdentifier]?.placeName
                let placeName = await resolvedPlaceName(for: snapshot, existingPlaceName: existingPlaceName)
                assets.append(snapshot.toPhotoAsset(placeName: placeName, now: now))
            }
            try await store.upsert(assets)
            upsertedCount += assets.count
        }

        // Under "Selected Photos" limited access, PHAsset fetch only
        // enumerates the user's currently-selected subset — a stored id
        // absent from that fetch might just be outside the current
        // selection, not actually removed from the library. Treating
        // "missing from a limited fetch" as "deleted" would silently
        // soft-delete every previously-indexed photo outside the selection
        // the moment access is downgraded from full to limited. Only a
        // full-access sync can safely prune; skip deletions entirely while
        // limited. (Found in review: Codex + independent Claude subagent
        // both flagged this as a silent-data-loss path.)
        var deletedCount = 0
        if !access.isLimitedAccess, !plan.idsToMarkDeleted.isEmpty {
            try await store.markDeleted(ids: plan.idsToMarkDeleted)
            deletedCount = plan.idsToMarkDeleted.count
        }

        return IngestResult(
            isLimitedAccess: access.isLimitedAccess,
            totalLibraryAssets: snapshots.count,
            gpsCoverage: coverage,
            upsertedCount: upsertedCount,
            deletedCount: deletedCount
        )
    }

    // Geocoding already retried internally against GeocodingRetryPolicy
    // (ReverseGeocoder) — a failure here means retries were exhausted.
    // Degrades to `existingPlaceName` rather than aborting the whole
    // ingest run: a re-upserted asset (already had a resolved place name
    // from an earlier sync) keeps it instead of having it overwritten with
    // nil by a transient failure — found in review (Codex): the original
    // unconditional `nil` fallback silently erased previously-good data on
    // every re-upsert that happened to hit a failed geocode. For a
    // genuinely new asset, existingPlaceName is nil, so this still
    // degrades to nil as before. Known limitation, not fixed in this pass:
    // SyncPlanner's diff is keyed on PHAsset modificationDate, not "missing
    // place_name", so a new asset that lands here stays ungeocoded until a
    // future targeted backfill pass — plain relaunch sync won't retry it on
    // its own unless the asset is otherwise modified.
    private func resolvedPlaceName(for snapshot: PhotoAssetSnapshot, existingPlaceName: String?) async -> String? {
        guard let latitude = snapshot.latitude, let longitude = snapshot.longitude else { return nil }
        do {
            return try await geocoder.placeName(latitude: latitude, longitude: longitude)
        } catch {
            let appError = (error as? AppError) ?? .geocodingFailed(underlying: error)
            errorReporter.report(appError, context: "PhotoLibraryIngestor.resolvedPlaceName")
            return existingPlaceName
        }
    }
}
