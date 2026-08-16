import Testing
import Foundation
@testable import GeoImageSearch

private struct FixedPlaceNameResolver: PlaceNameResolving {
    func resolve(placeName: String) async throws -> (latitude: Double, longitude: Double) { (0, 0) }
}

// Always returns the next canned turn in order; throws once exhausted.
private final class QueueLLMClient: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var turns: [LLMTurn]

    init(turns: [LLMTurn]) {
        self.turns = turns
    }

    func send(messages: [LLMMessage], tools: [OpenAITool]) async throws -> LLMTurn {
        let next: LLMTurn? = lock.withLock {
            guard !turns.isEmpty else { return nil }
            return turns.removeFirst()
        }
        guard let turn = next else { throw AppError.llmTimeout }
        return turn
    }
}

private struct ThrowingLLMClient: LLMClient {
    let error: AppError
    func send(messages: [LLMMessage], tools: [OpenAITool]) async throws -> LLMTurn { throw error }
}

private final class CapturingErrorReporting: ErrorReporting, @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [(AppError, String)] = []

    func report(_ error: AppError, context: String) {
        lock.withLock { reports.append((error, context)) }
    }

    var count: Int { lock.withLock { reports.count } }
    var lastContext: String? { lock.withLock { reports.last?.1 } }
}

private final class CapturingGlobeUpdater: GlobeUpdating, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pinCalls: [[GlobePin]] = []
    private(set) var highlightCalls: [[String]] = []
    private(set) var focusCalls: [GlobeBounds] = []

    func setPins(_ pins: [GlobePin]) async { lock.withLock { pinCalls.append(pins) } }
    func focusRegion(_ bounds: GlobeBounds) async { lock.withLock { focusCalls.append(bounds) } }
    func highlightAssets(ids: [String]) async { lock.withLock { highlightCalls.append(ids) } }
}

@MainActor
private func makeViewModel(
    llmClient: any LLMClient,
    photoQuery: any PhotoQuery & Sendable,
    apiKeyManager: APIKeyManager,
    errorReporting: CapturingErrorReporting = CapturingErrorReporting(),
    globeUpdater: CapturingGlobeUpdater = CapturingGlobeUpdater()
) -> ChatViewModel {
    let executor = ToolExecutor(photoQuery: photoQuery, placeNameResolver: FixedPlaceNameResolver())
    let agent = PhotoQueryAgent(llmClient: llmClient, toolExecutor: executor)
    return ChatViewModel(apiKeyManager: apiKeyManager, agent: agent, globeUpdater: globeUpdater, errorReporting: errorReporting)
}

@MainActor
@Suite struct ChatViewModelTests {
    @Test func refreshAPIKeyStateReflectsManager() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        try await apiKeyManager.save("sk-test")
        let viewModel = makeViewModel(llmClient: QueueLLMClient(turns: []), photoQuery: query, apiKeyManager: apiKeyManager)

        await viewModel.refreshAPIKeyState()

        #expect(viewModel.apiKeyState == .valid)
    }

    @Test func saveAPIKeyUpdatesState() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .invalid))
        let viewModel = makeViewModel(llmClient: QueueLLMClient(turns: []), photoQuery: query, apiKeyManager: apiKeyManager)

        await viewModel.saveAPIKey("sk-bad")

        #expect(viewModel.apiKeyState == .invalid)
    }

    @Test func clearAPIKeyResetsToMissing() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        let viewModel = makeViewModel(llmClient: QueueLLMClient(turns: []), photoQuery: query, apiKeyManager: apiKeyManager)
        await viewModel.saveAPIKey("sk-test")

        viewModel.clearAPIKey()

        #expect(viewModel.apiKeyState == .missing)
    }

    @Test func sendAppendsUserAndAssistantMessagesAndUpdatesGlobe() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        // FixedPlaceNameResolver always resolves to (0, 0); keep the fixture
        // within query_by_location's default 50km radius of that.
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "p1", latitude: 0.01, longitude: 0.01)])
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        let globeUpdater = CapturingGlobeUpdater()
        let client = QueueLLMClient(turns: [
            .toolCalls([LLMToolCall(id: "call_1", name: "query_by_location", argumentsJSON: #"{"placeName":"Somewhere"}"#)]),
            .message("Found your photo.")
        ])
        let viewModel = makeViewModel(llmClient: client, photoQuery: query, apiKeyManager: apiKeyManager, globeUpdater: globeUpdater)
        viewModel.draftText = "Where's my photo?"

        await viewModel.send()

        #expect(viewModel.messages.map(\.text) == ["Where's my photo?", "Found your photo."])
        #expect(viewModel.messages.map(\.role) == [.user, .assistant])
        #expect(viewModel.draftText.isEmpty)
        #expect(viewModel.isSending == false)
        #expect(globeUpdater.pinCalls.last == [GlobePin(id: "p1", lat: 0.01, lon: 0.01)])
        #expect(globeUpdater.highlightCalls.last == ["p1"])
    }

    @Test func sendIgnoresBlankDraft() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        let viewModel = makeViewModel(llmClient: QueueLLMClient(turns: []), photoQuery: query, apiKeyManager: apiKeyManager)
        viewModel.draftText = "   "

        await viewModel.send()

        #expect(viewModel.messages.isEmpty)
    }

    @Test func sendPreservesConversationAcrossMultipleTurns() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        let client = QueueLLMClient(turns: [.message("first"), .message("second")])
        let viewModel = makeViewModel(llmClient: client, photoQuery: query, apiKeyManager: apiKeyManager)

        viewModel.draftText = "one"
        await viewModel.send()
        viewModel.draftText = "two"
        await viewModel.send()

        #expect(viewModel.messages.map(\.text) == ["one", "first", "two", "second"])
    }

    @Test func sendOnInvalidAPIKeyErrorFlipsStateAndReports() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let apiKeyManager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        try await apiKeyManager.save("sk-test")
        let errorReporting = CapturingErrorReporting()
        let viewModel = makeViewModel(
            llmClient: ThrowingLLMClient(error: .llmInvalidAPIKey),
            photoQuery: query,
            apiKeyManager: apiKeyManager,
            errorReporting: errorReporting
        )
        viewModel.draftText = "anything"

        await viewModel.send()

        #expect(viewModel.apiKeyState == .invalid)
        #expect(errorReporting.count == 1)
        #expect(errorReporting.lastContext == "ChatViewModel.send")
        #expect(viewModel.messages.last?.text.contains("invalid") == true)
    }
}
