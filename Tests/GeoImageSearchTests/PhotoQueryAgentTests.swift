import Testing
import Foundation
@testable import GeoImageSearch

private enum ScriptError: Error {
    case scriptExhausted
}

private final class ScriptedLLMClient: LLMClient, @unchecked Sendable {
    private let lock = NSLock()
    private var script: [LLMTurn]
    private(set) var receivedMessages: [[LLMMessage]] = []

    init(script: [LLMTurn]) {
        self.script = script
    }

    func send(messages: [LLMMessage], tools: [OpenAITool]) async throws -> LLMTurn {
        let next: LLMTurn? = lock.withLock {
            receivedMessages.append(messages)
            guard !script.isEmpty else { return nil }
            return script.removeFirst()
        }
        guard let turn = next else { throw ScriptError.scriptExhausted }
        return turn
    }
}

private struct AlwaysOriginPlaceNameResolver: PlaceNameResolving {
    func resolve(placeName: String) async throws -> (latitude: Double, longitude: Double) { (0, 0) }
}

@Suite struct PhotoQueryAgentTests {
    @Test func returnsImmediatelyWhenModelAnswersWithNoToolCalls() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: AlwaysOriginPlaceNameResolver())
        let client = ScriptedLLMClient(script: [.message("You haven't been anywhere yet.")])
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor)

        let result = try await agent.ask("Where have I been?")

        #expect(result.responseText == "You haven't been anywhere yet.")
        #expect(result.assets.isEmpty)
    }

    @Test func executesToolCallThenReturnsFinalAnswer() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "athens-1", latitude: 0, longitude: 0)])
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: AlwaysOriginPlaceNameResolver())
        let client = ScriptedLLMClient(script: [
            .toolCalls([LLMToolCall(id: "call_1", name: "query_by_location", argumentsJSON: #"{"placeName":"Athens"}"#)]),
            .message("Found 1 photo near Athens.")
        ])
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor)

        let result = try await agent.ask("Find photos from Athens")

        #expect(result.responseText == "Found 1 photo near Athens.")
        #expect(result.assets.map(\.id) == ["athens-1"])
        // Second call to the model should include the tool-role result.
        #expect(client.receivedMessages.count == 2)
        #expect(client.receivedMessages[1].contains { $0.role == .tool && $0.toolCallID == "call_1" })
    }

    @Test func dedupesAssetsAcrossMultipleToolCallsInOneTurn() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "shared", latitude: 0, longitude: 0),
            PhotoAssetFixtures.makeAsset(id: "date-only", latitude: nil, longitude: nil, capturedAt: Date(timeIntervalSince1970: 1_700_000_000))
        ])
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: AlwaysOriginPlaceNameResolver())
        let client = ScriptedLLMClient(script: [
            .toolCalls([
                LLMToolCall(id: "call_1", name: "query_by_location", argumentsJSON: #"{"placeName":"Origin"}"#),
                LLMToolCall(id: "call_2", name: "query_by_date_range", argumentsJSON: #"{"start":"2023-11-01","end":"2023-11-30"}"#)
            ]),
            .message("done")
        ])
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor)

        let result = try await agent.ask("everything")

        // "shared" appears in both the location and date-range result sets
        // (its capturedAt also falls in November 2023) — should be counted once.
        #expect(Set(result.assets.map(\.id)) == ["shared", "date-only"])
        #expect(result.assets.count == 2)
    }

    @Test func toolExecutionErrorBecomesToolMessageRatherThanCrashingTurn() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: AlwaysOriginPlaceNameResolver())
        let client = ScriptedLLMClient(script: [
            .toolCalls([LLMToolCall(id: "call_1", name: "not_a_real_tool", argumentsJSON: "{}")]),
            .message("Sorry, I couldn't do that.")
        ])
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor)

        let result = try await agent.ask("do the impossible thing")

        #expect(result.responseText == "Sorry, I couldn't do that.")
        let toolMessage = client.receivedMessages[1].first { $0.role == .tool }
        #expect(toolMessage?.content?.contains("Error") == true)
    }

    @Test func throwsAfterExceedingMaxIterations() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: AlwaysOriginPlaceNameResolver())
        let neverEndingScript = (0..<(PhotoQueryAgent.maxIterations + 1)).map { _ in
            LLMTurn.toolCalls([LLMToolCall(id: "call", name: "cluster_trips", argumentsJSON: "{}")])
        }
        let client = ScriptedLLMClient(script: neverEndingScript)
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor)

        await #expect(throws: AgentLoopError.self) {
            _ = try await agent.ask("keep going forever")
        }
    }

    @Test func systemMessageGroundsRelativeDatesInProvidedCurrentDate() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: AlwaysOriginPlaceNameResolver())
        let client = ScriptedLLMClient(script: [.message("ok")])
        let fixedDate = ToolSchemas.dateOnlyFormatter.date(from: "2026-08-16")!
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor, currentDateProvider: { fixedDate })

        _ = try await agent.ask("what did I do last summer?")

        let systemMessage = client.receivedMessages[0].first { $0.role == .system }
        #expect(systemMessage?.content?.contains("2026-08-16") == true)
    }
}
