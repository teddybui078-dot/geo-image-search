import CoreGraphics
import Foundation
import Photos

// Keyed by assetID: String only — never exposes PHAsset — so EmbeddingQueue
// stays fully testable with a fake, no real Photos access needed.
protocol PhotoThumbnailFetching: Sendable {
    func prewarm(assetIDs: [String]) async
    func fetchThumbnail(assetID: String) async throws -> CGImage
}

extension PhotoThumbnailFetching {
    func prewarm(assetIDs: [String]) async {}
}

// Resolves PhotoAsset.id (a PHAsset.localIdentifier) to a real PHAsset
// itself — photo-icloud-extraction hasn't built real ingestion yet, so
// there's no shared asset-lookup code to depend on.
private actor ResolvedAssetCache {
    private var assetsByID: [String: PHAsset] = [:]

    func store(_ assets: [PHAsset]) {
        for asset in assets {
            assetsByID[asset.localIdentifier] = asset
        }
    }

    func lookup(_ id: String) -> PHAsset? {
        assetsByID[id]
    }
}

// PHImageManager's completion handler resuming a continuation more than
// once is a hard crash — .fastFormat + isNetworkAccessAllowed = false is
// expected to call back exactly once, but this guards against relying on
// that being contractually guaranteed rather than just commonly true.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        body()
    }
}

final class PHPhotoThumbnailFetcher: PhotoThumbnailFetching {
    private let imageManager: PHImageManager
    private let cache = ResolvedAssetCache()
    private let targetSize: CGSize

    init(imageManager: PHImageManager = .default(), targetSize: CGSize = CGSize(width: 320, height: 320)) {
        self.imageManager = imageManager
        self.targetSize = targetSize
    }

    // One batch PHAsset.fetchAssets(withLocalIdentifiers:) call instead of
    // one lookup per asset — called once up front by EmbeddingQueue before
    // its bounded-concurrency loop starts.
    func prewarm(assetIDs: [String]) async {
        guard !assetIDs.isEmpty else { return }
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var assets: [PHAsset] = []
        assets.reserveCapacity(fetchResult.count)
        fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }
        await cache.store(assets)
    }

    func fetchThumbnail(assetID: String) async throws -> CGImage {
        guard let asset = await cache.lookup(assetID) else {
            throw EmbeddingPipelineError.assetNotFound(localIdentifier: assetID)
        }

        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        // DESIGN.md's explicit framing: embedding generation reads
        // PhotosKit's local thumbnail, not a full-resolution iCloud fetch.
        options.isNetworkAccessAllowed = false
        options.isSynchronous = false

        return try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = ResumeOnce()
            imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, info in
                resumeOnce.run {
                    if let cgImage = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        continuation.resume(returning: cgImage)
                    } else {
                        let reason = "\(info ?? [:])"
                        continuation.resume(throwing: EmbeddingPipelineError.thumbnailUnavailable(assetLocalIdentifier: assetID, reason: reason))
                    }
                }
            }
        }
    }
}
