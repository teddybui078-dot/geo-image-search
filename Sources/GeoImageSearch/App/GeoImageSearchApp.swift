import SwiftUI

@main
struct GeoImageSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Shows onboarding until it's actually done, then bootstraps local storage
// and hosts the globe (or its fallback) alongside the chat agent, plus a
// manual sync trigger (photo-icloud-extraction). Storage open failures
// aren't modeled by AppError — CONTRACT.md's enum covers PhotosKit/
// CLGeocoder/LLM/webview failures, not local storage bootstrap — so this is
// a plain error state rather than a forced-fit AppError case.
struct ContentView: View {
    private let errorReporter: any ErrorReporting = ErrorReporter()

    private let onboardingProgress: any OnboardingProgressStoring = UserDefaultsOnboardingProgressStore()
    private let agentPreferencesStore: any AgentPreferencesStoring = UserDefaultsAgentPreferencesStore()
    private let photosAuthorizing: any PhotosAuthorizing = PhotosPermissionManager()

    @State private var onboardingRequirements: OnboardingRequirements?

    @State private var chatViewModel: ChatViewModel?
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
                    preferencesStore: agentPreferencesStore,
                    photosAuthorizing: photosAuthorizing,
                    onComplete: {
                        let requirements = resolveOnboardingRequirements()
                        self.onboardingRequirements = requirements
                        if requirements.isComplete {
                            Task { await bootstrap() }
                        }
                    }
                )
            } else if let storageError {
                Text("Couldn't open local storage: \(storageError)")
                    .padding()
            } else if let photoQuery, let chatViewModel {
                HSplitView {
                    VStack(spacing: 0) {
                        syncBar
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
                    .frame(minWidth: 360)

                    ChatView(viewModel: chatViewModel)
                        .frame(minWidth: 320)
                }
            } else {
                ProgressView("Opening your library…")
                    .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 480)
        .task {
            let requirements = resolveOnboardingRequirements()
            onboardingRequirements = requirements
            if requirements.isComplete {
                await bootstrap()
            }
        }
    }

    private func resolveOnboardingRequirements() -> OnboardingRequirements {
        OnboardingRequirementsResolver.resolve(progress: onboardingProgress, photosAuthorizing: photosAuthorizing)
    }

    private var syncBar: some View {
        HStack {
            Text(syncStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            // Manual trigger for TODOS.md item 6: validate real GPS coverage
            // % against the user's own library. No polished onboarding UI
            // yet — this exists so that number can actually be measured by
            // running the app (via Xcode, not `swift run`/`swift test`,
            // neither of which carries the Photos entitlement) against a
            // real library.
            Button(isSyncing ? "Syncing…" : "Sync Photo Library") {
                Task { await runIngestion() }
            }
            .disabled(isSyncing)
        }
        .padding(8)
    }

    private func bootstrap() async {
        do {
            let (store, query) = try await AppComposition.openPhotoStore()
            photoStore = store
            photoQuery = query
            chatViewModel = try await AppComposition.makeChatViewModel(query: query)
        } catch {
            storageError = error.localizedDescription
        }
    }

    private func runIngestion() async {
        guard let photoStore, let photoQuery else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let result = try await PhotoLibraryIngestor(store: photoStore, query: photoQuery, errorReporter: errorReporter).run()
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
