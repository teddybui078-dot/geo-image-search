import Foundation

// The Sendable value-type read off a PhotoLibraryAsset (PHAsset in
// production) immediately at the fetch boundary — see PhotoLibraryAsset.swift
// for why. Everything downstream (diffing, geocoding, upserting) operates on
// this, never on PHAsset itself.
struct PhotoAssetSnapshot: Sendable, Equatable {
    let localIdentifier: String
    let latitude: Double?
    let longitude: Double?
    let creationDate: Date?
    let modificationDate: Date?
    let isLivePhoto: Bool

    // Live Photos are indexed as photos only, motion ignored (v1) — CONTRACT.md's
    // PhotoAsset.isLivePhoto. mediaSubtypes.contains(.photoLive) is the only
    // signal PhotosKit exposes for this; there's no separate "is this a Live
    // Photo" boolean on PHAsset.
    init(
        localIdentifier: String,
        latitude: Double?,
        longitude: Double?,
        creationDate: Date?,
        modificationDate: Date?,
        isLivePhoto: Bool
    ) {
        self.localIdentifier = localIdentifier
        self.latitude = latitude
        self.longitude = longitude
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.isLivePhoto = isLivePhoto
    }

    init(asset: any PhotoLibraryAsset) {
        self.init(
            localIdentifier: asset.localIdentifier,
            latitude: asset.location?.coordinate.latitude,
            longitude: asset.location?.coordinate.longitude,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            isLivePhoto: asset.mediaSubtypes.contains(.photoLive)
        )
    }

    // The sync diff's change signal (SyncPlanner) — PHAsset.modificationDate
    // is what we actually compare against a stored PhotoAsset.updatedAt, so
    // this is also what gets written back as updatedAt on upsert. Falls back
    // to creationDate, then `now`, for the rare asset missing both.
    func effectiveUpdatedAt(now: Date) -> Date {
        modificationDate ?? creationDate ?? now
    }

    func toPhotoAsset(placeName: String?, now: Date) -> PhotoAsset {
        PhotoAsset(
            id: localIdentifier,
            latitude: latitude,
            longitude: longitude,
            // capturedAt is the domain timestamp (when the photo was taken);
            // createdAt/updatedAt are bookkeeping columns. creationDate is
            // essentially always present for real photos, but PHAsset
            // declares it optional, so fall back rather than force-unwrap.
            capturedAt: creationDate ?? modificationDate ?? now,
            // SQLitePhotoStore's upsert ON CONFLICT DO UPDATE never touches
            // created_at, so this value only matters the first time this id
            // is upserted — safe to always pass `now`.
            createdAt: now,
            updatedAt: effectiveUpdatedAt(now: now),
            deletedAt: nil,
            placeName: placeName,
            isLivePhoto: isLivePhoto
        )
    }
}

// TODOS.md item 6 — measure real GPS coverage against the user's own
// library early. Pure over snapshots so it's testable without PhotosKit.
struct GPSCoverageReport: Sendable, Equatable {
    let totalAssets: Int
    let assetsWithGPS: Int

    var coveragePercent: Double {
        totalAssets == 0 ? 0 : Double(assetsWithGPS) / Double(totalAssets) * 100
    }

    static func measure(_ snapshots: [PhotoAssetSnapshot]) -> GPSCoverageReport {
        let withGPS = snapshots.lazy.filter { $0.latitude != nil && $0.longitude != nil }.count
        return GPSCoverageReport(totalAssets: snapshots.count, assetsWithGPS: withGPS)
    }
}
