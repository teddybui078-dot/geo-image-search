import Foundation

struct AgentTurnResult: Sendable {
    let responseText: String
    let assets: [PhotoAsset]           // aggregated across every tool call this turn, deduped — for GlobeUpdating
    let updatedMessages: [LLMMessage]  // full conversation including this turn — pass back in as the next call's priorMessages to keep multi-turn memory
}

enum AgentLoopError: Error {
    case exceededMaxIterations
}

// Multi-turn tool-calling loop: send the conversation + ToolSchemas.all to
// LLMClient; while the response is tool calls, run each through
// ToolExecutor, append tool-role results, and loop until the model returns
// a final message. Bounded iteration count guards against a runaway loop
// (e.g. the model repeatedly calling tools without ever answering).
final class PhotoQueryAgent: Sendable {
    static let maxIterations = 8

    private let llmClient: any LLMClient
    private let toolExecutor: ToolExecutor
    private let currentDateProvider: @Sendable () -> Date

    init(
        llmClient: any LLMClient,
        toolExecutor: ToolExecutor,
        currentDateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.llmClient = llmClient
        self.toolExecutor = toolExecutor
        self.currentDateProvider = currentDateProvider
    }

    func ask(_ question: String, priorMessages: [LLMMessage] = []) async throws -> AgentTurnResult {
        var messages = priorMessages.isEmpty ? [systemMessage()] : priorMessages
        messages.append(.user(question))

        var aggregatedAssets: [PhotoAsset] = []
        var seenAssetIDs = Set<String>()

        for _ in 0..<Self.maxIterations {
            let turn = try await llmClient.send(messages: messages, tools: ToolSchemas.all)
            switch turn {
            case .message(let text):
                messages.append(.assistant(content: text, toolCalls: nil))
                return AgentTurnResult(responseText: text, assets: aggregatedAssets, updatedMessages: messages)
            case .toolCalls(let calls):
                messages.append(.assistant(content: nil, toolCalls: calls))
                for call in calls {
                    let resultText: String
                    do {
                        let result = try await toolExecutor.execute(toolCall: call)
                        for asset in result.assets where !seenAssetIDs.contains(asset.id) {
                            seenAssetIDs.insert(asset.id)
                            aggregatedAssets.append(asset)
                        }
                        resultText = result.summary
                    } catch {
                        // Fed back to the model as a tool-role error message
                        // so it can recover (adjust params, explain the
                        // failure to the user) instead of the whole turn
                        // crashing on one bad tool call.
                        resultText = "Error: \(String(describing: error))"
                    }
                    messages.append(.toolResult(callID: call.id, content: resultText))
                }
            }
        }
        throw AgentLoopError.exceededMaxIterations
    }

    private func systemMessage() -> LLMMessage {
        let today = ToolSchemas.dateOnlyFormatter.string(from: currentDateProvider())
        return .system("""
            You are a helpful assistant answering questions about the user's own geotagged photo library. \
            Today's date is \(today). Resolve relative date phrasing ("last summer", "in 2022", "last month") \
            to concrete YYYY-MM-DD dates before calling query_by_date_range. Use the available tools to answer \
            questions grounded in the user's actual photos — never invent photos, places, or dates a tool didn't \
            return. If a tool returns no results, say so plainly.
            """)
    }
}
