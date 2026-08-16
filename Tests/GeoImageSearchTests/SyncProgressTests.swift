import Testing
@testable import GeoImageSearch

@Suite @MainActor struct SyncProgressTests {
    @Test func startsIdle() {
        let progress = SyncProgress()
        #expect(progress.phase == .idle)
    }

    @Test func startSetsSyncingPhaseWithZeroProcessed() {
        let progress = SyncProgress()
        progress.start(total: 10)
        #expect(progress.phase == .syncing(processed: 0, total: 10))
    }

    @Test func recordProgressAccumulates() {
        let progress = SyncProgress()
        progress.start(total: 3)

        progress.recordProgress()
        #expect(progress.phase == .syncing(processed: 1, total: 3))

        progress.recordProgress()
        progress.recordProgress()
        #expect(progress.phase == .syncing(processed: 3, total: 3))
    }

    @Test func setPhaseTransitionsToFetchingLibrary() {
        let progress = SyncProgress()
        progress.setPhase(.fetchingLibrary)
        #expect(progress.phase == .fetchingLibrary)
    }

    @Test func finishSetsFinishedPhaseWithResult() {
        let progress = SyncProgress()
        progress.start(total: 2)
        progress.recordProgress()

        let result = IngestResult(
            isLimitedAccess: false,
            totalLibraryAssets: 2,
            gpsCoverage: GPSCoverageReport(totalAssets: 2, assetsWithGPS: 1),
            upsertedCount: 2,
            deletedCount: 0
        )
        progress.finish(result)

        #expect(progress.phase == .finished(result))
    }

    @Test func failSetsFailedPhaseWithMessage() {
        let progress = SyncProgress()
        progress.start(total: 1)
        progress.fail("Sync failed: boom")
        #expect(progress.phase == .failed("Sync failed: boom"))
    }
}
