import Photos

// The PhotosKit/iCloud boundary PhotosRetryPolicy exists for (CONTRACT.md,
// AppError.photosFetchFailed). Declared `throws` for two reasons: it lets
// PhotoLibraryIngestor route real failures through
// RetryExecutor.run(policy: PhotosRetryPolicy()), and it lets tests inject a
// fake that fails N times to prove that retry path actually engages —
// PHAsset.fetchAssets(with:) itself is a synchronous, local, metadata-only
// call that doesn't throw at the SDK level, but iCloud sync hiccups during
// that fetch are a real enough failure mode for a boundary this feature
// explicitly owns to be worth wrapping defensively.
protocol PhotoLibraryFetching: Sendable {
    func fetchAllPhotoAssetSnapshots() throws -> [PhotoAssetSnapshot]
}

// Real assets only — mediaType == .image covers both stills and Live Photos
// (a Live Photo's still is a PHAsset with mediaType .image and
// mediaSubtypes containing .photoLive; the paired video is not a separate
// fetched asset). Plain video assets are out of scope for a photo/geo app.
struct PHPhotoLibraryFetcher: PhotoLibraryFetching {
    func fetchAllPhotoAssetSnapshots() throws -> [PhotoAssetSnapshot] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)

        var snapshots: [PhotoAssetSnapshot] = []
        snapshots.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            snapshots.append(PhotoAssetSnapshot(asset: asset))
        }
        return snapshots
    }
}
