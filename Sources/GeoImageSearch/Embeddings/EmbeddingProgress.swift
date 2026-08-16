import Foundation
import Observation

// There's no real app shell yet to wire a progress view into permanently
// (GeoImageSearchApp.swift is still a placeholder) — this is a UI-framework
// -agnostic observable state object EmbeddingQueue drives from its
// background tasks, so a SwiftUI view (EmbeddingProgressView) can bind to
// it once there's somewhere real to put one. @MainActor-isolated: all
// mutation is main-actor-serialized, so it's safe to observe from SwiftUI
// without extra synchronization even though updates originate off-actor.
@MainActor
@Observable
final class EmbeddingProgress {
    enum Phase: Equatable {
        case idle
        case provisioningModel(fraction: Double)
        case queryingLibrary
        case embedding
        case finished
    }

    private(set) var totalCount = 0
    private(set) var completedCount = 0
    private(set) var failedCount = 0
    private(set) var phase: Phase = .idle

    init() {}

    func setPhase(_ phase: Phase) {
        self.phase = phase
    }

    func start(total: Int) {
        totalCount = total
        completedCount = 0
        failedCount = 0
        phase = .embedding
    }

    func recordSuccess() {
        completedCount += 1
    }

    func recordFailure() {
        failedCount += 1
    }

    func finish() {
        phase = .finished
    }
}
