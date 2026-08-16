import CoreGraphics
import Foundation

enum GallerySlot: Equatable {
    case skeleton
    case loaded(CGImage)

    static func == (lhs: GallerySlot, rhs: GallerySlot) -> Bool {
        switch (lhs, rhs) {
        case (.skeleton, .skeleton):
            return true
        case (.loaded(let a), .loaded(let b)):
            return a === b
        default:
            return false
        }
    }
}

// Drives the photo grid: fetches real thumbnails via PhotoThumbnailFetching
// (the same seam embedding-pipeline uses — no new PhotosKit code needed),
// but reveals them revealBatchSize at a time with a short pause between
// batches so the grid fills in visibly instead of popping in all at once.
@MainActor
final class PhotoGalleryViewModel: ObservableObject {
    @Published private(set) var slots: [GallerySlot] = []

    // DESIGN.md scales for personal libraries up to ~50k photos — a grid
    // dump of the whole library isn't useful or fast, so this caps to a
    // recent slice rather than paginating (no design call for pagination
    // yet; revisit if this becomes the primary browsing surface).
    private static let maxPhotos = 60

    private let photoQuery: any PhotoQuery & Sendable
    private let thumbnailFetching: any PhotoThumbnailFetching
    private let revealBatchSize: Int
    private let revealDelay: Duration

    init(
        photoQuery: any PhotoQuery & Sendable,
        thumbnailFetching: any PhotoThumbnailFetching,
        revealBatchSize: Int = 5,
        revealDelay: Duration = .milliseconds(200)
    ) {
        self.photoQuery = photoQuery
        self.thumbnailFetching = thumbnailFetching
        self.revealBatchSize = revealBatchSize
        self.revealDelay = revealDelay
    }

    func load() async {
        let assets: [PhotoAsset]
        do {
            assets = try await photoQuery.allActivePhotosWithLocation()
        } catch {
            slots = []
            return
        }

        let recent = Array(assets.sorted { $0.capturedAt > $1.capturedAt }.prefix(Self.maxPhotos))
        guard !recent.isEmpty else {
            slots = []
            return
        }

        slots = Array(repeating: .skeleton, count: recent.count)
        let assetIDs = recent.map(\.id)
        await thumbnailFetching.prewarm(assetIDs: assetIDs)

        for batchStart in stride(from: 0, to: assetIDs.count, by: revealBatchSize) {
            let batchEnd = min(batchStart + revealBatchSize, assetIDs.count)
            let batchIndices = Array(batchStart..<batchEnd)

            await withTaskGroup(of: (Int, CGImage?).self) { group in
                for index in batchIndices {
                    let assetID = assetIDs[index]
                    group.addTask {
                        let image = try? await self.thumbnailFetching.fetchThumbnail(assetID: assetID)
                        return (index, image)
                    }
                }
                for await (index, image) in group {
                    // A failed fetch leaves that slot .skeleton rather than
                    // failing the whole batch — matches
                    // PHPhotoThumbnailFetcher's per-asset error cases.
                    if let image {
                        slots[index] = .loaded(image)
                    }
                }
            }

            if batchEnd < assetIDs.count {
                try? await Task.sleep(for: revealDelay)
            }
        }
    }
}
