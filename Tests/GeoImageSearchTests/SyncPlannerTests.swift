import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct SyncPlannerTests {
    private func snapshot(_ id: String, modificationDate: Date?) -> PhotoAssetSnapshot {
        PhotoAssetSnapshot(
            localIdentifier: id,
            latitude: nil, longitude: nil,
            creationDate: modificationDate,
            modificationDate: modificationDate,
            isLivePhoto: false
        )
    }

    private func stored(_ updatedAt: Date, placeName: String? = nil) -> StoredPhotoIdentity {
        StoredPhotoIdentity(updatedAt: updatedAt, placeName: placeName)
    }

    @Test func emptyStoreUpsertsEveryAsset() {
        // First-launch case: an empty stored set means everything is "new" —
        // no separate one-shot-ingest branch.
        let library = [snapshot("a", modificationDate: .now), snapshot("b", modificationDate: .now)]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: [:])

        #expect(Set(plan.toUpsert.map(\.localIdentifier)) == ["a", "b"])
        #expect(plan.idsToMarkDeleted.isEmpty)
    }

    @Test func unchangedAssetIsSkipped() {
        let modifiedAt = Date(timeIntervalSince1970: 1000)
        let library = [snapshot("a", modificationDate: modifiedAt)]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: ["a": stored(modifiedAt)])

        #expect(plan.toUpsert.isEmpty)
        #expect(plan.idsToMarkDeleted.isEmpty)
    }

    @Test func changedAssetIsReUpserted() {
        let library = [snapshot("a", modificationDate: Date(timeIntervalSince1970: 2000))]

        let plan = SyncPlanner.plan(
            librarySnapshots: library,
            storedIdentifiers: ["a": stored(Date(timeIntervalSince1970: 1000))]
        )

        #expect(plan.toUpsert.map(\.localIdentifier) == ["a"])
    }

    // Regression: `updated_at` is stored as a whole-second SQLite INTEGER
    // (DateConversion.unixSecondsClamped truncates), but PHAsset.modificationDate
    // almost always carries fractional seconds. storedIdentifiers here is
    // exactly what allActiveIdentifiers() returns after that round trip —
    // fractional seconds must not make an untouched asset look "changed".
    @Test func subSecondModificationDateDoesNotLookChangedAfterStoreRoundTrip() {
        let modifiedAt = Date(timeIntervalSince1970: 1000.789)
        let roundTrippedStoredValue = Date(timeIntervalSince1970: TimeInterval(modifiedAt.unixSecondsClamped))
        let library = [snapshot("a", modificationDate: modifiedAt)]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: ["a": stored(roundTrippedStoredValue)])

        #expect(plan.toUpsert.isEmpty)
    }

    // Regression: an asset missing both creationDate and modificationDate
    // used to fall back to a fresh `now` every run, which is always later
    // than whatever `now` got stored last run — perpetually "changed"
    // forever. The fixed fallback (a stable epoch sentinel) must make a
    // second sync of the same dateless asset look unchanged, exactly like
    // any other asset.
    @Test func datelessAssetIsIdempotentAcrossSyncs() {
        let snap = snapshot("dateless", modificationDate: nil)
        let firstSyncStored = snap.effectiveUpdatedAt

        let plan = SyncPlanner.plan(librarySnapshots: [snap], storedIdentifiers: ["dateless": stored(firstSyncStored)])

        #expect(plan.toUpsert.isEmpty)
    }

    @Test func missingFromLibraryIsMarkedDeleted() {
        let plan = SyncPlanner.plan(
            librarySnapshots: [],
            storedIdentifiers: ["gone": stored(Date(timeIntervalSince1970: 1000))]
        )

        #expect(plan.toUpsert.isEmpty)
        #expect(plan.idsToMarkDeleted == ["gone"])
    }

    @Test func mixedPlanCoversNewChangedUnchangedAndDeleted() {
        let storedIdentifiers: [String: StoredPhotoIdentity] = [
            "unchanged": stored(Date(timeIntervalSince1970: 1000)),
            "changed": stored(Date(timeIntervalSince1970: 1000)),
            "deleted": stored(Date(timeIntervalSince1970: 1000))
        ]
        let library = [
            snapshot("unchanged", modificationDate: Date(timeIntervalSince1970: 1000)),
            snapshot("changed", modificationDate: Date(timeIntervalSince1970: 2000)),
            snapshot("new", modificationDate: Date(timeIntervalSince1970: 3000))
        ]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: storedIdentifiers)

        #expect(Set(plan.toUpsert.map(\.localIdentifier)) == ["changed", "new"])
        #expect(plan.idsToMarkDeleted == ["deleted"])
    }
}
