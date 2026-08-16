import CoreGraphics
import Foundation
import Testing
@testable import GeoImageSearch

private struct FakePhotoQuery: PhotoQuery, Sendable {
    var assets: [PhotoAsset] = []

    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset] { [] }
    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset] { [] }
    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset] { [] }
    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster] { [] }
    func allActivePhotosWithLocation() async throws -> [PhotoAsset] { assets }
    func allActiveIdentifiers() async throws -> [String: StoredPhotoIdentity] { [:] }
}

private actor FakeThumbnailFetcher: PhotoThumbnailFetching {
    private var failingAssetIDs: Set<String>
    private(set) var prewarmedAssetIDs: [String] = []

    init(failingAssetIDs: Set<String> = []) {
        self.failingAssetIDs = failingAssetIDs
    }

    func prewarm(assetIDs: [String]) async {
        prewarmedAssetIDs = assetIDs
    }

    func fetchThumbnail(assetID: String) async throws -> CGImage {
        if failingAssetIDs.contains(assetID) {
            throw EmbeddingPipelineError.thumbnailUnavailable(assetLocalIdentifier: assetID, reason: "fake failure")
        }
        return Self.fixtureImage
    }

    static let fixtureImage: CGImage = {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context.makeImage()!
    }()
}

@MainActor
@Suite("PhotoGalleryViewModel")
struct PhotoGalleryViewModelTests {
    @Test("empty library produces no slots")
    func emptyLibrary() async {
        let viewModel = PhotoGalleryViewModel(
            photoQuery: FakePhotoQuery(assets: []),
            thumbnailFetching: FakeThumbnailFetcher(),
            revealDelay: .zero
        )
        await viewModel.load()
        #expect(viewModel.slots.isEmpty)
    }

    @Test("all slots load and end up newest-first")
    func loadsAllSlotsNewestFirst() async {
        let older = PhotoAssetFixtures.makeAsset(id: "older", capturedAt: Date(timeIntervalSince1970: 0))
        let newer = PhotoAssetFixtures.makeAsset(id: "newer", capturedAt: Date(timeIntervalSince1970: 1000))
        let query = FakePhotoQuery(assets: [older, newer])
        let fetcher = FakeThumbnailFetcher()

        let viewModel = PhotoGalleryViewModel(photoQuery: query, thumbnailFetching: fetcher, revealBatchSize: 5, revealDelay: .zero)
        await viewModel.load()

        #expect(viewModel.slots.count == 2)
        #expect(viewModel.slots.allSatisfy { $0 == .loaded(FakeThumbnailFetcher.fixtureImage) })
        let prewarmed = await fetcher.prewarmedAssetIDs
        #expect(prewarmed == ["newer", "older"])
    }

    @Test("a failed thumbnail fetch leaves that slot skeleton, others still load")
    func failedFetchStaysSkeleton() async {
        let a = PhotoAssetFixtures.makeAsset(id: "a", capturedAt: Date(timeIntervalSince1970: 0))
        let b = PhotoAssetFixtures.makeAsset(id: "b", capturedAt: Date(timeIntervalSince1970: 1))
        let query = FakePhotoQuery(assets: [a, b])
        let fetcher = FakeThumbnailFetcher(failingAssetIDs: ["a"])

        let viewModel = PhotoGalleryViewModel(photoQuery: query, thumbnailFetching: fetcher, revealBatchSize: 5, revealDelay: .zero)
        await viewModel.load()

        #expect(viewModel.slots.count == 2)
        #expect(viewModel.slots.contains(.skeleton))
        #expect(viewModel.slots.contains(.loaded(FakeThumbnailFetcher.fixtureImage)))
    }

    @Test("more than the display cap is truncated to the most recent ones")
    func capsToMostRecent() async {
        let assets = (0..<70).map { PhotoAssetFixtures.makeAsset(id: "\($0)", capturedAt: Date(timeIntervalSince1970: Double($0))) }
        let query = FakePhotoQuery(assets: assets)
        let fetcher = FakeThumbnailFetcher()

        let viewModel = PhotoGalleryViewModel(photoQuery: query, thumbnailFetching: fetcher, revealBatchSize: 5, revealDelay: .zero)
        await viewModel.load()

        #expect(viewModel.slots.count == 60)
        let prewarmed = await fetcher.prewarmedAssetIDs
        // Newest 60 by capturedAt: ids 69 down to 10.
        #expect(prewarmed.first == "69")
        #expect(prewarmed.last == "10")
    }
}
