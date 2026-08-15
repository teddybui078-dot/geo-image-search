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
        storedIdentifiers: [String: StoredPhotoIdentity]
    ) -> Plan {
        let libraryIDs = Set(librarySnapshots.map(\.localIdentifier))

        let toUpsert = librarySnapshots.filter { snapshot in
            guard let stored = storedIdentifiers[snapshot.localIdentifier] else {
                return true // absent from the store — new asset
            }
            // Compare at whole-second precision via unixSecondsClamped, not
            // as raw Dates: `updated_at` is stored as a SQLite INTEGER
            // (DateConversion.unixSecondsClamped truncates fractional
            // seconds on write), so stored.updatedAt always lands on a
            // whole second. PHAsset.modificationDate almost always carries
            // fractional seconds — comparing it untruncated against a
            // truncated stored value with strict `>` was true on nearly
            // every asset, every run, silently turning "incremental diff"
            // back into "re-upsert (and re-geocode) everything every
            // relaunch." Truncating both sides the same way is what makes
            // "unchanged since last sync" actually mean unchanged.
            //
            // Residual limitation, not fixable without a schema change:
            // two genuine modifications to the same asset landing within
            // the same whole second (both sides then truncate to the same
            // value) would be missed. CONTRACT.md's `updated_at INTEGER`
            // column is locked, and two real edits within one second is
            // rare enough for a personal library that this isn't worth a
            // migration to fix.
            return snapshot.effectiveUpdatedAt.unixSecondsClamped > stored.updatedAt.unixSecondsClamped
        }

        // Stored but missing from the fresh enumeration — the library no
        // longer has it. Soft-deleted, not hard-deleted (PhotoStore.markDeleted).
        // Caller (PhotoLibraryIngestor) is responsible for NOT acting on
        // this under limited Photos access, where "missing from the fetch"
        // doesn't mean "actually gone" — see its own comment for why.
        let idsToMarkDeleted = storedIdentifiers.keys.filter { !libraryIDs.contains($0) }

        return Plan(toUpsert: toUpsert, idsToMarkDeleted: idsToMarkDeleted)
    }
}
