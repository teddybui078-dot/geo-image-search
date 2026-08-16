import Foundation

// Wires up the concrete dependencies ChatViewModel needs. Kept separate
// from GeoImageSearchApp/ContentView so the wiring is a single, obvious
// place to update as photo-icloud-extraction and add-3dmap land their own
// real implementations.
enum AppComposition {
    // TODOS.md item 5 — the CoreML embedding model isn't picked yet, so
    // this is a placeholder (CONTRACT.md's original draft dimension) until
    // embedding-pipeline chooses a real MobileCLIP variant. A mismatch
    // against the eventual real model throws SQLiteError.embeddingDimensionMismatch
    // at query time rather than failing silently.
    static let placeholderEmbeddingDimension = 512

    @MainActor
    static func makeChatViewModel() async throws -> ChatViewModel {
        let (_, query) = try await openPhotoStore()
        let keyStore = KeychainKeyStore()
        let openAIClient = OpenAIClient(apiKeyProvider: {
            guard let key = try keyStore.read(), !key.isEmpty else {
                throw AgentConfigurationError.missingAPIKey
            }
            return key
        })
        let apiKeyManager = APIKeyManager(store: keyStore, validator: openAIClient)
        let agent = PhotoQueryAgent(
            llmClient: openAIClient,
            toolExecutor: ToolExecutor(photoQuery: query, placeNameResolver: PlaceNameResolver())
        )
        return ChatViewModel(
            apiKeyManager: apiKeyManager,
            agent: agent,
            globeUpdater: LoggingGlobeUpdater(),
            errorReporting: ErrorReporter()
        )
    }

    // Shared with ContentView's manual "Sync Photo Library" trigger
    // (TODOS.md item 6) so both point at the exact same database file —
    // photo-icloud-extraction's ingestor and the chat agent's PhotoQuery
    // independently invented their own path/filename before this branch
    // merged main; a divergent path here would mean a sync is invisible to
    // the agent (or vice versa), so this is the one place either caller
    // should get it from.
    static func openPhotoStore() async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        let path = try databaseURL().path
        return try await SQLiteDatabase.open(atPath: path, embeddingDimension: placeholderEmbeddingDimension)
    }

    static func databaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("GeoImageSearch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("library.sqlite")
    }
}
