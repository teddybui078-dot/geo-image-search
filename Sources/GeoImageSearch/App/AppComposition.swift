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
        let query = try await openPhotoQuery()
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

    private static func openPhotoQuery() async throws -> SQLitePhotoQuery {
        let directory = try applicationSupportDirectory()
        let path = directory.appendingPathComponent("geoimagesearch.sqlite").path
        let (_, query) = try await SQLiteDatabase.open(atPath: path, embeddingDimension: placeholderEmbeddingDimension)
        return query
    }

    private static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("GeoImageSearch", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
