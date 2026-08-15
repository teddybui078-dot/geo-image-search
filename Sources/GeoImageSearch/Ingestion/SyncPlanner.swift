import Foundation

// Next Step 1a's decision — documented in full in CONTRACT.md's "Relaunch
// sync strategy" section: full library enumeration every launch (cheap,
// metadata-only, no image bytes), diffed client-side against
// PhotoQuery.allActiveIdentifiers() using PHAsset.modificationDate
// (PhotoAssetSnapshot.effectiveUpdatedAt) as the change signal, not Apple's
// PHPersistentChangeToken API. First launch falls out of the same code path
// for free — the stored identifier set is empty, so every enumerated asset
// is "new" — no separate one-shot-ingest branch needed.
enum SyncPlanner {
    struct Plan: Sendable, Equatable {
        let toUpsert: [PhotoAssetSnapshot]
        let idsToMarkDeleted: [String]
    }

    static func plan(
        librarySnapshots: [PhotoAssetSnapshot],
        storedIdentifiers: [String: Date],
        now: Date
    ) -> Plan {
        let libraryIDs = Set(librarySnapshots.map(\.localIdentifier))

        let toUpsert = librarySnapshots.filter { snapshot in
            guard let storedUpdatedAt = storedIdentifiers[snapshot.localIdentifier] else {
                return true // absent from the store — new asset
            }
            // Strict `>`, not `>=`: an asset whose modificationDate exactly
            // matches what's already stored is unchanged since the last
            // sync — skipping it avoids a redundant write (and, once
            // geocoding is wired in ahead of it, a redundant CLGeocoder call).
            return snapshot.effectiveUpdatedAt(now: now) > storedUpdatedAt
        }

        // Stored but missing from the fresh enumeration — the library no
        // longer has it. Soft-deleted, not hard-deleted (PhotoStore.markDeleted).
        let idsToMarkDeleted = storedIdentifiers.keys.filter { !libraryIDs.contains($0) }

        return Plan(toUpsert: toUpsert, idsToMarkDeleted: idsToMarkDeleted)
    }
}
