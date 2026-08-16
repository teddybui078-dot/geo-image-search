import SwiftUI

// Minimal — not wired into ContentView, there's no real app shell yet
// (GeoImageSearchApp.swift is still a placeholder). Exists so a later
// integration merge has something to drop in rather than starting from
// scratch, and so this worktree's progress-reporting requirement has a
// visible, working UI, not just an observable model.
struct EmbeddingProgressView: View {
    var progress: EmbeddingProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch progress.phase {
            case .idle:
                Text("Not running")
                    .foregroundStyle(.secondary)

            case .provisioningModel(let fraction):
                Text("Downloading embedding model…")
                ProgressView(value: fraction)

            case .queryingLibrary:
                ProgressView("Finding photos to embed…")

            case .embedding:
                Text(embeddingStatusText)
                ProgressView(
                    value: Double(progress.completedCount + progress.failedCount),
                    total: Double(max(progress.totalCount, 1))
                )

            case .finished:
                Label(finishedSummaryText, systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var embeddingStatusText: String {
        "Embedding photos: \(progress.completedCount + progress.failedCount) of \(progress.totalCount)"
    }

    private var finishedSummaryText: String {
        progress.failedCount > 0
            ? "Embedded \(progress.completedCount) photos, \(progress.failedCount) failed"
            : "Embedded \(progress.completedCount) photos"
    }
}
