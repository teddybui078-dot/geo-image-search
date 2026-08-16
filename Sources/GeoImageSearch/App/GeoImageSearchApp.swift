import SwiftUI

@main
struct GeoImageSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var status = "Geo Image Search — foundations laid, Next Step 1 starts here."
    @State private var isRunning = false

    var body: some View {
        VStack(spacing: 16) {
            Text(status)
                .multilineTextAlignment(.center)
            // Manual trigger for TODOS.md item 6: validate real GPS coverage
            // % against the user's own library. No polished UI yet — this
            // exists so that number can actually be measured by running the
            // app (via Xcode, not `swift run`/`swift test`, neither of which
            // carries the Photos entitlement) against a real library.
            Button(isRunning ? "Syncing…" : "Sync Photo Library") {
                Task { await runIngestion() }
            }
            .disabled(isRunning)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 200)
    }

    private func runIngestion() async {
        isRunning = true
        defer { isRunning = false }
        do {
            let dbURL = try Self.databaseURL()
            // 512 is the real MobileCLIP-S2 embedding dimension now (TODOS.md
            // item 5, CONTRACT.md's "Model choice, resolved"), not a
            // placeholder — this sync flow just doesn't happen to write any
            // embeddings itself, that's embedding-pipeline's job.
            let (store, query) = try await SQLiteDatabase.open(atPath: dbURL.path, embeddingDimension: EmbeddingModelInfo.embeddingDimension)
            let result = try await PhotoLibraryIngestor(store: store, query: query).run()
            status = """
            Synced \(result.totalLibraryAssets) photos — \(result.upsertedCount) written, \(result.deletedCount) removed.
            GPS coverage: \(String(format: "%.1f", result.gpsCoverage.coveragePercent))% (\(result.gpsCoverage.assetsWithGPS)/\(result.gpsCoverage.totalAssets))
            \(result.isLimitedAccess ? "⚠️ Limited Photos access — only a subset of the library is visible." : "")
            """
        } catch {
            status = "Sync failed: \(error)"
        }
    }

    private static func databaseURL() throws -> URL {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let appDir = supportDir.appendingPathComponent("GeoImageSearch", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("library.sqlite")
    }
}
