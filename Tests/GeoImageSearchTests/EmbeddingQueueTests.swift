import CoreGraphics
import Foundation
import Testing
@testable import GeoImageSearch

// Fully fake-driven — no real CoreML model or Photos access. EmbeddingQueue
// is injected against protocol existentials specifically so this is
// possible; see EmbeddingQueue.swift's header comment.

private struct FakePhotoQuery: PhotoQuery, Sendable {
    var assets: [PhotoAsset] = []
    var embedded: Set<String> = []

    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset] { [] }
    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset] { assets }
    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset] { [] }
    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster] { [] }
    func allActivePhotosWithLocation() async throws -> [PhotoAsset] { [] }
    func embeddedAssetIDs(modelVersion: String) async throws -> Set<String> { embedded }
}

private actor FakePhotoStore: PhotoStore {
    private(set) var upsertedEmbeddings: [EmbeddingRecord] = []

    func upsert(_ assets: [PhotoAsset]) async throws {}
    func markDeleted(ids: [String]) async throws {}

    func upsertEmbedding(_ record: EmbeddingRecord) async throws {
        upsertedEmbeddings.append(record)
    }
}

private struct FakeModelProvisioning: ModelProvisioning {
    func localURL(for asset: EmbeddingModelAsset) -> URL {
        URL(fileURLWithPath: "/tmp/fake-\(asset.fileName)")
    }

    func ensureAvailable(_ asset: EmbeddingModelAsset, onProgress: (@Sendable (Double) -> Void)?) async throws -> URL {
        onProgress?(1.0)
        return localURL(for: asset)
    }
}

private struct FakeImageEmbedder: ImageEmbedding {
    var vector: [Float] = [0.1, 0.2, 0.3, 0.4]
    func embed(cgImage: CGImage) async throws -> [Float] { vector }
}

private actor FakeThumbnailFetcher: PhotoThumbnailFetching {
    private var failingAssetIDs: Set<String>
    private let delayNanoseconds: UInt64
    private(set) var inFlightCount = 0
    private(set) var maxInFlightCount = 0
    private(set) var prewarmedAssetIDs: [String] = []

    init(failingAssetIDs: Set<String> = [], delayNanoseconds: UInt64 = 2_000_000) {
        self.failingAssetIDs = failingAssetIDs
        self.delayNanoseconds = delayNanoseconds
    }

    func prewarm(assetIDs: [String]) async {
        prewarmedAssetIDs = assetIDs
    }

    func fetchThumbnail(assetID: String) async throws -> CGImage {
        inFlightCount += 1
        maxInFlightCount = max(maxInFlightCount, inFlightCount)
        if delayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
        }
        inFlightCount -= 1

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

private final class FakeErrorReporting: ErrorReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [(error: AppError, context: String)] = []

    func report(_ error: AppError, context: String) {
        lock.lock()
        storage.append((error, context))
        lock.unlock()
    }

    var reportedErrors: [(error: AppError, context: String)] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

// Skips real backoff wall-clock time (EmbeddingRetryPolicy backs off up to
// 4s per attempt) — tests only care that retries happened, not how long.
private struct ImmediateDelaying: RetryDelaying {
    func delay(_ duration: TimeInterval) async throws {}
}

// EmbeddingProgress is @MainActor-isolated (see its header comment) — this
// suite runs on the main actor so its init() and property reads don't need
// an await at every call site.
@Suite @MainActor struct EmbeddingQueueTests {
    private func makeQueue(
        assets: [PhotoAsset],
        embedded: Set<String> = [],
        thumbnailFetcher: FakeThumbnailFetcher = FakeThumbnailFetcher(),
        photoStore: FakePhotoStore = FakePhotoStore(),
        errorReporting: FakeErrorReporting = FakeErrorReporting(),
        configuration: EmbeddingQueueConfiguration = .init()
    ) -> EmbeddingQueue {
        EmbeddingQueue(
            photoQuery: FakePhotoQuery(assets: assets, embedded: embedded),
            photoStore: photoStore,
            modelProvisioner: FakeModelProvisioning(),
            thumbnailFetcher: thumbnailFetcher,
            errorReporter: errorReporting,
            progress: EmbeddingProgress(),
            configuration: configuration,
            imageEmbedderFactory: { _ in FakeImageEmbedder() },
            retryDelaying: ImmediateDelaying()
        )
    }

    @Test func happyPathEmbedsAllAssetsAndWritesRecords() async throws {
        let assets = (1...5).map { PhotoAssetFixtures.makeAsset(id: "asset-\($0)") }
        let photoStore = FakePhotoStore()
        let progress = EmbeddingProgress()
        let queue = EmbeddingQueue(
            photoQuery: FakePhotoQuery(assets: assets),
            photoStore: photoStore,
            modelProvisioner: FakeModelProvisioning(),
            thumbnailFetcher: FakeThumbnailFetcher(),
            errorReporter: FakeErrorReporting(),
            progress: progress,
            imageEmbedderFactory: { _ in FakeImageEmbedder() },
            retryDelaying: ImmediateDelaying()
        )

        try await queue.run()

        let written = await photoStore.upsertedEmbeddings
        #expect(written.count == 5)
        #expect(Set(written.map(\.assetID)) == Set(assets.map(\.id)))
        #expect(written.allSatisfy { $0.modelVersion == EmbeddingModelInfo.modelVersion })
        #expect(written.allSatisfy { $0.vector == [0.1, 0.2, 0.3, 0.4] })

        #expect(progress.totalCount == 5)
        #expect(progress.completedCount == 5)
        #expect(progress.failedCount == 0)
        #expect(progress.phase == .finished)
    }

    @Test func oneFailingAssetDoesNotAbortBatchAndIsReportedOnce() async throws {
        let assets = (1...4).map { PhotoAssetFixtures.makeAsset(id: "asset-\($0)") }
        let thumbnailFetcher = FakeThumbnailFetcher(failingAssetIDs: ["asset-2"], delayNanoseconds: 0)
        let photoStore = FakePhotoStore()
        let errorReporting = FakeErrorReporting()
        let progress = EmbeddingProgress()
        let queue = EmbeddingQueue(
            photoQuery: FakePhotoQuery(assets: assets),
            photoStore: photoStore,
            modelProvisioner: FakeModelProvisioning(),
            thumbnailFetcher: thumbnailFetcher,
            errorReporter: errorReporting,
            progress: progress,
            imageEmbedderFactory: { _ in FakeImageEmbedder() },
            retryDelaying: ImmediateDelaying()
        )

        try await queue.run()

        let written = await photoStore.upsertedEmbeddings
        #expect(written.count == 3)
        #expect(!written.contains { $0.assetID == "asset-2" })

        #expect(errorReporting.reportedErrors.count == 1)
        if case .embeddingGenerationFailed(let assetID, _) = errorReporting.reportedErrors.first?.error {
            #expect(assetID == "asset-2")
        } else {
            Issue.record("expected embeddingGenerationFailed for asset-2")
        }

        #expect(progress.completedCount == 3)
        #expect(progress.failedCount == 1)
    }

    @Test func skipAlreadyEmbeddedFiltersCandidatesWhenEnabled() async throws {
        let assets = (1...3).map { PhotoAssetFixtures.makeAsset(id: "asset-\($0)") }
        let photoStore = FakePhotoStore()
        let queue = makeQueue(assets: assets, embedded: ["asset-2"], photoStore: photoStore)

        try await queue.run()

        let written = await photoStore.upsertedEmbeddings
        #expect(written.count == 2)
        #expect(!written.contains { $0.assetID == "asset-2" })
    }

    @Test func skipAlreadyEmbeddedDisabledReEmbedsEverything() async throws {
        let assets = (1...3).map { PhotoAssetFixtures.makeAsset(id: "asset-\($0)") }
        let photoStore = FakePhotoStore()
        let queue = makeQueue(
            assets: assets,
            embedded: ["asset-2"],
            photoStore: photoStore,
            configuration: EmbeddingQueueConfiguration(skipAlreadyEmbedded: false)
        )

        try await queue.run()

        let written = await photoStore.upsertedEmbeddings
        #expect(written.count == 3)
    }

    @Test func respectsMaxConcurrentThumbnailFetchesBound() async throws {
        let assets = (1...12).map { PhotoAssetFixtures.makeAsset(id: "asset-\($0)") }
        let thumbnailFetcher = FakeThumbnailFetcher(delayNanoseconds: 5_000_000)
        let queue = makeQueue(
            assets: assets,
            thumbnailFetcher: thumbnailFetcher,
            configuration: EmbeddingQueueConfiguration(maxConcurrentThumbnailFetches: 3)
        )

        try await queue.run()

        let maxInFlight = await thumbnailFetcher.maxInFlightCount
        #expect(maxInFlight <= 3)
        #expect(maxInFlight > 1) // sanity: fetches actually overlapped, the bound isn't accidentally serial
    }

    @Test func prewarmsThumbnailFetcherWithCandidateAssetIDsOnly() async throws {
        let assets = (1...3).map { PhotoAssetFixtures.makeAsset(id: "asset-\($0)") }
        let thumbnailFetcher = FakeThumbnailFetcher(delayNanoseconds: 0)
        let queue = makeQueue(assets: assets, embedded: ["asset-2"], thumbnailFetcher: thumbnailFetcher)

        try await queue.run()

        let prewarmed = await thumbnailFetcher.prewarmedAssetIDs
        #expect(Set(prewarmed) == ["asset-1", "asset-3"])
    }
}
