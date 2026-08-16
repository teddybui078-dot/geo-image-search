import Foundation

// Wires up the concrete dependencies ChatViewModel needs. Kept separate
// from GeoImageSearchApp/ContentView so the wiring is a single, obvious
// place to update as photo-icloud-extraction and add-3dmap land their own
// real implementations.
enum AppComposition {
    // Shares the store/query ContentView already opened (via openPhotoStore()
    // below) rather than opening its own second connection to the same
    // database file.
    @MainActor
    static func makeChatViewModel(query: any PhotoQuery & Sendable) async throws -> ChatViewModel {
        let keyStore = KeychainKeyStore()
        let openAIClient = OpenAIClient(apiKeyProvider: {
            guard let key = try keyStore.read(), !key.isEmpty else {
                throw AgentConfigurationError.missingAPIKey
            }
            return key
        })
        let agent = PhotoQueryAgent(
            llmClient: openAIClient,
            toolExecutor: ToolExecutor(photoQuery: query, placeNameResolver: PlaceNameResolver())
        )
        return ChatViewModel(
            apiKeyManager: makeAPIKeyManager(keyStore: keyStore, validator: openAIClient),
            agent: agent,
            globeUpdater: LoggingGlobeUpdater(),
            errorReporting: ErrorReporter()
        )
    }

    // Onboarding's API key step needs the exact same Keychain-backed
    // manager as ChatView — a key saved during onboarding must be what the
    // chat agent actually reads, not a second, out-of-sync Keychain entry.
    // keyStore/validator are injectable only so makeChatViewModel above can
    // reuse the ones it already built rather than constructing a second
    // KeychainKeyStore/OpenAIClient pair for the same process lifetime.
    static func makeAPIKeyManager(
        keyStore: KeychainKeyStore = KeychainKeyStore(),
        validator: (any APIKeyValidating)? = nil
    ) -> APIKeyManager {
        let resolvedValidator = validator ?? OpenAIClient(apiKeyProvider: {
            guard let key = try keyStore.read(), !key.isEmpty else {
                throw AgentConfigurationError.missingAPIKey
            }
            return key
        })
        return APIKeyManager(store: keyStore, validator: resolvedValidator)
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
        // TODOS.md item 5 is resolved (MobileCLIP-S2) — this is the real
        // dimension, not a placeholder, per CONTRACT.md's "Model choice, resolved".
        return try await SQLiteDatabase.open(atPath: path, embeddingDimension: EmbeddingModelInfo.embeddingDimension)
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
