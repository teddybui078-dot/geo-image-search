import SwiftUI

// Mirrors EmbeddingProgressView's switch-over-phase structure. Replaces the
// old static "Syncing…" button text with live status text plus, while the
// library is still being enumerated, a skeleton body — so a real sync (up
// to ~50k photos, per DESIGN.md) never reads as frozen.
struct SyncProgressView: View {
    var progress: SyncProgress

    var body: some View {
        switch progress.phase {
        case .idle:
            EmptyView()

        case .fetchingLibrary:
            VStack(alignment: .leading, spacing: 4) {
                Text("Pulling recent photos…")
                skeletonRows
            }

        case .syncing(let processed, let total):
            VStack(alignment: .leading, spacing: 4) {
                Text("Synced \(processed) of \(total)…")
                ProgressView(value: Double(processed), total: Double(max(total, 1)))
            }

        case .finished(let result):
            Text(finishedSummaryText(result))

        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
        }
    }

    private var skeletonRows: some View {
        // Real Text content run through .redacted(reason: .placeholder) is
        // the SwiftUI-native skeleton idiom — it renders as blurred bars
        // that already respect light/dark mode, no manual coloring needed.
        VStack(alignment: .leading, spacing: 4) {
            Text("Photo from a recent trip")
            Text("Another photo, roughly this wide")
            Text("A third placeholder row")
        }
        .redacted(reason: .placeholder)
    }

    private func finishedSummaryText(_ result: IngestResult) -> String {
        """
        Synced \(result.totalLibraryAssets) photos — \(result.upsertedCount) written, \(result.deletedCount) removed. \
        GPS coverage: \(String(format: "%.1f", result.gpsCoverage.coveragePercent))% (\(result.gpsCoverage.assetsWithGPS)/\(result.gpsCoverage.totalAssets))\
        \(result.isLimitedAccess ? " — ⚠️ limited Photos access, only a subset of the library is visible." : "")
        """
    }
}
