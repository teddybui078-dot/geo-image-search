import Testing
@testable import GeoImageSearch

@Suite @MainActor struct EmbeddingProgressTests {
    @Test func startsIdle() {
        let progress = EmbeddingProgress()
        #expect(progress.phase == .idle)
        #expect(progress.totalCount == 0)
        #expect(progress.completedCount == 0)
        #expect(progress.failedCount == 0)
    }

    @Test func startSetsTotalAndResetsCounts() {
        let progress = EmbeddingProgress()
        progress.recordSuccess()
        progress.recordFailure()

        progress.start(total: 10)

        #expect(progress.totalCount == 10)
        #expect(progress.completedCount == 0)
        #expect(progress.failedCount == 0)
        #expect(progress.phase == .embedding)
    }

    @Test func recordSuccessAndFailureAccumulateIndependently() {
        let progress = EmbeddingProgress()
        progress.start(total: 3)

        progress.recordSuccess()
        progress.recordSuccess()
        progress.recordFailure()

        #expect(progress.completedCount == 2)
        #expect(progress.failedCount == 1)
    }

    @Test func setPhaseTransitionsThroughProvisioningAndQuerying() {
        let progress = EmbeddingProgress()

        progress.setPhase(.provisioningModel(fraction: 0.25))
        #expect(progress.phase == .provisioningModel(fraction: 0.25))

        progress.setPhase(.provisioningModel(fraction: 1.0))
        #expect(progress.phase == .provisioningModel(fraction: 1.0))

        progress.setPhase(.queryingLibrary)
        #expect(progress.phase == .queryingLibrary)
    }

    @Test func finishSetsFinishedPhaseWithoutTouchingCounts() {
        let progress = EmbeddingProgress()
        progress.start(total: 2)
        progress.recordSuccess()

        progress.finish()

        #expect(progress.phase == .finished)
        #expect(progress.completedCount == 1)
        #expect(progress.totalCount == 2)
    }
}
