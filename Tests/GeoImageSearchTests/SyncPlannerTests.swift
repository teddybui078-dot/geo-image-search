import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct SyncPlannerTests {
    private func snapshot(_ id: String, modificationDate: Date) -> PhotoAssetSnapshot {
        PhotoAssetSnapshot(
            localIdentifier: id,
            latitude: nil, longitude: nil,
            creationDate: modificationDate,
            modificationDate: modificationDate,
            isLivePhoto: false
        )
    }

    @Test func emptyStoreUpsertsEveryAsset() {
        // First-launch case: an empty stored set means everything is "new" —
        // no separate one-shot-ingest branch.
        let library = [snapshot("a", modificationDate: .now), snapshot("b", modificationDate: .now)]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: [:], now: .now)

        #expect(Set(plan.toUpsert.map(\.localIdentifier)) == ["a", "b"])
        #expect(plan.idsToMarkDeleted.isEmpty)
    }

    @Test func unchangedAssetIsSkipped() {
        let modifiedAt = Date(timeIntervalSince1970: 1000)
        let library = [snapshot("a", modificationDate: modifiedAt)]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: ["a": modifiedAt], now: .now)

        #expect(plan.toUpsert.isEmpty)
        #expect(plan.idsToMarkDeleted.isEmpty)
    }

    @Test func changedAssetIsReUpserted() {
        let library = [snapshot("a", modificationDate: Date(timeIntervalSince1970: 2000))]

        let plan = SyncPlanner.plan(
            librarySnapshots: library,
            storedIdentifiers: ["a": Date(timeIntervalSince1970: 1000)],
            now: .now
        )

        #expect(plan.toUpsert.map(\.localIdentifier) == ["a"])
    }

    @Test func missingFromLibraryIsMarkedDeleted() {
        let plan = SyncPlanner.plan(
            librarySnapshots: [],
            storedIdentifiers: ["gone": Date(timeIntervalSince1970: 1000)],
            now: .now
        )

        #expect(plan.toUpsert.isEmpty)
        #expect(plan.idsToMarkDeleted == ["gone"])
    }

    @Test func mixedPlanCoversNewChangedUnchangedAndDeleted() {
        let stored: [String: Date] = [
            "unchanged": Date(timeIntervalSince1970: 1000),
            "changed": Date(timeIntervalSince1970: 1000),
            "deleted": Date(timeIntervalSince1970: 1000)
        ]
        let library = [
            snapshot("unchanged", modificationDate: Date(timeIntervalSince1970: 1000)),
            snapshot("changed", modificationDate: Date(timeIntervalSince1970: 2000)),
            snapshot("new", modificationDate: Date(timeIntervalSince1970: 3000))
        ]

        let plan = SyncPlanner.plan(librarySnapshots: library, storedIdentifiers: stored, now: .now)

        #expect(Set(plan.toUpsert.map(\.localIdentifier)) == ["changed", "new"])
        #expect(plan.idsToMarkDeleted == ["deleted"])
    }
}
