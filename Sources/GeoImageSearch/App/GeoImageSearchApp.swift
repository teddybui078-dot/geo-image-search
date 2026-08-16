import SwiftUI

@main
struct GeoImageSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Bootstraps local storage, then hosts a sync trigger (photo-icloud-extraction)
// above the globe (or its fallback). Storage open failures aren't modeled by
// AppError — CONTRACT.md's enum covers PhotosKit/CLGeocoder/LLM/webview
// failures, not local storage bootstrap — so this is a plain error state
// rather than a forced-fit AppError case.
struct ContentView: View {
    private let errorReporter: any ErrorReporting = ErrorReporter()

    private let onboardingProgress: any OnboardingProgressStoring = UserDefaultsOnboardingProgressStore()
    private let apiKeyStore: any APIKeyStoring = KeychainAPIKeyStore()
    private let agentPreferencesStore: any AgentPreferencesStoring = UserDefaultsAgentPreferencesStore()
    private let photosAuthorizing: any PhotosAuthorizing = PhotosPermissionManager()

    @State private var onboardingRequirements: OnboardingRequirements?

    @State private var photoStore: (any PhotoStore & Sendable)?
    @State private var photoQuery: (any PhotoQuery & Sendable)?
    @State private var storageError: String?
    @State private var loadFailed = false
    @State private var retryToken = 0

    @State private var syncStatus = "Not synced yet."
    @State private var isSyncing = false

    var body: some View {
        Group {
            if let onboardingRequirements, !onboardingRequirements.isComplete {
                OnboardingView(
                    requirements: onboardingRequirements,
                    progress: onboardingProgress,
                    apiKeyStore: apiKeyStore,
                    preferencesStore: agentPreferencesStore,
                    photosAuthorizing: photosAuthorizing,
                    onComplete: {
                        let requirements = resolveOnboardingRequirements()
                        self.onboardingRequirements = requirements
                        if requirements.isComplete {
                            Task { await openStorage() }
                        }
                    }
                )
            } else if let storageError {
                Text("Couldn't open local storage: \(storageError)")
                    .padding()
            } else if let photoStore, let photoQuery {
                VStack(spacing: 0) {
                    HStack {
                        Text(syncStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        // Manual trigger for TODOS.md item 6: validate real
                        // GPS coverage % against the user's own library. No
                        // polished UI yet — this exists so that number can
                        // actually be measured by running the app (via
                        // Xcode, not `swift run`/`swift test`, neither of
                        // which carries the Photos entitlement) against a
                        // real library.
                        Button(isSyncing ? "Syncing…" : "Sync Photo Library") {
                            Task { await runIngestion(store: photoStore, query: photoQuery) }
                        }
                        .disabled(isSyncing)
                    }
                    .padding(8)

                    if loadFailed {
                        GlobeFallbackView(onRetry: {
                            loadFailed = false
                            retryToken += 1
                        })
                    } else {
                        GlobeView(photoQuery: photoQuery, errorReporter: errorReporter, loadFailed: $loadFailed)
                            .id(retryToken)
                    }
                }
            } else {
                ProgressView("Opening your library…")
                    .padding()
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            let requirements = resolveOnboardingRequirements()
            onboardingRequirements = requirements
            if requirements.isComplete {
                await openStorage()
            }
        }
    }

    private func resolveOnboardingRequirements() -> OnboardingRequirements {
        OnboardingRequirementsResolver.resolve(progress: onboardingProgress, photosAuthorizing: photosAuthorizing)
    }

    private func openStorage() async {
        do {
            let directory = try AppPaths.photoDatabaseDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("library.sqlite").path
            // 512 is the real MobileCLIP-S2 embedding dimension now (TODOS.md
            // item 5, CONTRACT.md's "Model choice, resolved"), not a
            // placeholder — neither add-3dmap (reads
            // allActivePhotosWithLocation()) nor ingestion touches
            // photo_embeddings themselves, that's embedding-pipeline's job.
            let (store, query) = try await SQLiteDatabase.open(atPath: path, embeddingDimension: EmbeddingModelInfo.embeddingDimension)
            photoStore = store
            photoQuery = query
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func runIngestion(store: any PhotoStore & Sendable, query: any PhotoQuery & Sendable) async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await PhotoLibraryIngestor(store: store, query: query, errorReporter: errorReporter).run()
            syncStatus = """
            Synced \(result.totalLibraryAssets) photos — \(result.upsertedCount) written, \(result.deletedCount) removed. \
            GPS coverage: \(String(format: "%.1f", result.gpsCoverage.coveragePercent))% (\(result.gpsCoverage.assetsWithGPS)/\(result.gpsCoverage.totalAssets))\
            \(result.isLimitedAccess ? " — ⚠️ limited Photos access, only a subset of the library is visible." : "")
            """
            // Reloads GlobeView so it re-fetches allActivePhotosWithLocation()
            // and picks up whatever this sync just wrote.
            retryToken += 1
        } catch {
            syncStatus = "Sync failed: \(error)"
        }
    }
}

enum AppPaths {
    static func photoDatabaseDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("GeoImageSearch", isDirectory: true)
    }
}
