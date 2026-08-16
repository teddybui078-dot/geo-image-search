import CoreGraphics
import Foundation

struct EmbeddingQueueConfiguration: Sendable {
    var maxConcurrentThumbnailFetches = 4
    var skipAlreadyEmbedded = true

    init(maxConcurrentThumbnailFetches: Int = 4, skipAlreadyEmbedded: Bool = true) {
        self.maxConcurrentThumbnailFetches = maxConcurrentThumbnailFetches
        self.skipAlreadyEmbedded = skipAlreadyEmbedded
    }
}

// Background-queue, bounded-concurrency embedding generation with visible
// progress and an optional date-range scope for first-run indexing —
// TODOS.md item 5 / DESIGN.md Next Step 4. Fully dependency-injected
// against protocol existentials so it's testable without a real CoreML
// model or Photos access; wiring a real SQLiteConnection/PhotoStore and
// calling run() from the app is left for a later integration merge (there's
// no app-level DB bootstrap yet — GeoImageSearchApp.swift is still a
// placeholder).
final class EmbeddingQueue: Sendable {
    private let photoQuery: any PhotoQuery & Sendable
    private let photoStore: any PhotoStore & Sendable
    private let modelProvisioner: any ModelProvisioning
    private let thumbnailFetcher: any PhotoThumbnailFetching
    private let imageEmbedderFactory: @Sendable (URL) throws -> any ImageEmbedding
    private let errorReporter: any ErrorReporting
    private let progress: EmbeddingProgress
    private let configuration: EmbeddingQueueConfiguration
    private let retryDelaying: any RetryDelaying

    init(
        photoQuery: any PhotoQuery & Sendable,
        photoStore: any PhotoStore & Sendable,
        modelProvisioner: any ModelProvisioning,
        thumbnailFetcher: any PhotoThumbnailFetching,
        errorReporter: any ErrorReporting,
        progress: EmbeddingProgress,
        configuration: EmbeddingQueueConfiguration = .init(),
        imageEmbedderFactory: @escaping @Sendable (URL) throws -> any ImageEmbedding = { try ImageEmbedder(modelURL: $0) },
        retryDelaying: any RetryDelaying = TaskSleepDelaying()
    ) {
        self.photoQuery = photoQuery
        self.photoStore = photoStore
        self.modelProvisioner = modelProvisioner
        self.thumbnailFetcher = thumbnailFetcher
        self.errorReporter = errorReporter
        self.progress = progress
        self.retryDelaying = retryDelaying
        self.configuration = configuration
        self.imageEmbedderFactory = imageEmbedderFactory
    }

    /// Embeds every active photo in `dateRange` (unscoped = the whole
    /// library, via `.distantPast...distantFuture` — safe per
    /// `Date.unixSecondsClamped`). Individual asset failures are retried
    /// and, on exhaustion, reported — never abort the batch.
    func run(dateRange: ClosedRange<Date>? = nil) async throws {
        await progress.setPhase(.provisioningModel(fraction: 0))
        let imageModelURL = try await modelProvisioner.ensureAvailable(.image) { [progress] fraction in
            Task { @MainActor in progress.setPhase(.provisioningModel(fraction: fraction)) }
        }
        let embedder = try imageEmbedderFactory(imageModelURL)

        await progress.setPhase(.queryingLibrary)
        let range = dateRange ?? (Date.distantPast ... Date.distantFuture)
        var candidates = try await photoQuery.byDateRange(start: range.lowerBound, end: range.upperBound)

        if configuration.skipAlreadyEmbedded {
            let alreadyEmbedded = try await photoQuery.embeddedAssetIDs(modelVersion: EmbeddingModelInfo.modelVersion)
            candidates.removeAll { alreadyEmbedded.contains($0.id) }
        }

        await thumbnailFetcher.prewarm(assetIDs: candidates.map(\.id))
        await progress.start(total: candidates.count)

        await withTaskGroup(of: Void.self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<max(configuration.maxConcurrentThumbnailFetches, 1) {
                guard let next = iterator.next() else { break }
                group.addTask { await self.processAsset(next, embedder: embedder) }
            }
            while await group.next() != nil {
                if let next = iterator.next() {
                    group.addTask { await self.processAsset(next, embedder: embedder) }
                }
            }
        }

        await progress.finish()
    }

    // Never throws out of the task group — a failing asset is retried,
    // reported on exhaustion, and the batch continues.
    private func processAsset(_ asset: PhotoAsset, embedder: any ImageEmbedding) async {
        do {
            try await RetryExecutor.run(policy: EmbeddingRetryPolicy(), delaying: retryDelaying) {
                try await self.embedAndStore(asset, embedder: embedder)
            }
            await progress.recordSuccess()
        } catch let error as AppError {
            errorReporter.report(error, context: "EmbeddingQueue")
            await progress.recordFailure()
        } catch {
            // RetryExecutor only ever rethrows what embedAndStore throws,
            // and embedAndStore only ever throws AppError — unreachable in
            // practice, but still reported rather than silently dropped.
            errorReporter.report(
                .embeddingGenerationFailed(assetID: asset.id, underlying: error),
                context: "EmbeddingQueue"
            )
            await progress.recordFailure()
        }
    }

    private func embedAndStore(_ asset: PhotoAsset, embedder: any ImageEmbedding) async throws {
        let cgImage: CGImage
        do {
            cgImage = try await thumbnailFetcher.fetchThumbnail(assetID: asset.id)
        } catch {
            throw AppError.embeddingGenerationFailed(
                assetID: asset.id,
                underlying: EmbeddingPipelineError.thumbnailUnavailable(assetLocalIdentifier: asset.id, reason: "\(error)")
            )
        }

        let vector: [Float]
        do {
            vector = try await embedder.embed(cgImage: cgImage)
        } catch {
            throw AppError.embeddingGenerationFailed(
                assetID: asset.id,
                underlying: EmbeddingPipelineError.inferenceFailed(underlying: error)
            )
        }

        do {
            try await photoStore.upsertEmbedding(EmbeddingRecord(
                assetID: asset.id,
                vector: vector,
                modelVersion: EmbeddingModelInfo.modelVersion,
                generatedAt: Date()
            ))
        } catch {
            throw AppError.embeddingGenerationFailed(assetID: asset.id, underlying: error)
        }
    }
}
