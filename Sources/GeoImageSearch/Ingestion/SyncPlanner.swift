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
            // Compare at whole-second precision via unixSecondsClamped, not
            // as raw Dates: `updated_at` is stored as a SQLite INTEGER
            // (DateConversion.unixSecondsClamped truncates fractional
            // seconds on write), so storedUpdatedAt always lands on a whole
            // second. PHAsset.modificationDate almost always carries
            // fractional seconds — comparing it untruncated against a
            // truncated stored value with strict `>` was true on nearly
            // every asset, every run, silently turning "incremental diff"
            // back into "re-upsert (and re-geocode) everything every
            // relaunch." Truncating both sides the same way is what makes
            // "unchanged since last sync" actually mean unchanged.
            return snapshot.effectiveUpdatedAt(now: now).unixSecondsClamped > storedUpdatedAt.unixSecondsClamped
        }

        // Stored but missing from the fresh enumeration — the library no
        // longer has it. Soft-deleted, not hard-deleted (PhotoStore.markDeleted).
        let idsToMarkDeleted = storedIdentifiers.keys.filter { !libraryIDs.contains($0) }

        return Plan(toUpsert: toUpsert, idsToMarkDeleted: idsToMarkDeleted)
    }
}
