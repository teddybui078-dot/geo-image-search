import Foundation
import Observation

// Mirrors Embeddings/EmbeddingProgress.swift's shape exactly — same
// @MainActor-isolated, @Observable pattern so PhotoLibraryIngestor's
// background sync task can report into it and a SwiftUI view
// (SyncProgressView) can bind to it without extra synchronization.
@MainActor
@Observable
final class SyncProgress {
    enum Phase: Equatable {
        case idle
        case fetchingLibrary
        case syncing(processed: Int, total: Int)
        case finished(IngestResult)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private var total = 0
    private var processed = 0

    init() {}

    func setPhase(_ phase: Phase) {
        self.phase = phase
    }

    func start(total: Int) {
        self.total = total
        processed = 0
        phase = .syncing(processed: 0, total: total)
    }

    func recordProgress() {
        processed += 1
        phase = .syncing(processed: processed, total: total)
    }

    func finish(_ result: IngestResult) {
        phase = .finished(result)
    }

    func fail(_ message: String) {
        phase = .failed(message)
    }
}
