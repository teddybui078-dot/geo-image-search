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
    @State private var viewModel: ChatViewModel?
    @State private var bootstrapError: String?
    @State private var syncStatus: String?
    @State private var isSyncing = false

    var body: some View {
        Group {
            if let viewModel {
                ChatView(viewModel: viewModel)
                    .safeAreaInset(edge: .top) {
                        if let syncStatus {
                            Text(syncStatus)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.thinMaterial)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(isSyncing ? "Syncing…" : "Sync Photo Library") {
                                Task { await runIngestion() }
                            }
                            .disabled(isSyncing)
                        }
                    }
            } else if let bootstrapError {
                Text("Failed to start: \(bootstrapError)")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView("Starting Geo Image Search…")
            }
        }
        .task {
            do {
                viewModel = try await AppComposition.makeChatViewModel()
            } catch {
                bootstrapError = error.localizedDescription
            }
        }
    }

    // Manual trigger for TODOS.md item 6: validate real GPS coverage % against
    // the user's own library. No polished onboarding UI yet — this exists so
    // that number can actually be measured by running the app (via Xcode, not
    // `swift run`/`swift test`, neither of which carries the Photos
    // entitlement) against a real library. Shares AppComposition's database
    // path with the chat agent's PhotoQuery, so a sync here is immediately
    // visible to it.
    private func runIngestion() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let (store, query) = try await AppComposition.openPhotoStore()
            let result = try await PhotoLibraryIngestor(store: store, query: query).run()
            syncStatus = """
            Synced \(result.totalLibraryAssets) photos — \(result.upsertedCount) written, \(result.deletedCount) removed. \
            GPS coverage: \(String(format: "%.1f", result.gpsCoverage.coveragePercent))% (\(result.gpsCoverage.assetsWithGPS)/\(result.gpsCoverage.totalAssets))\
            \(result.isLimitedAccess ? " ⚠️ Limited Photos access — only a subset of the library is visible." : "")
            """
        } catch {
            syncStatus = "Sync failed: \(error)"
        }
    }
}
