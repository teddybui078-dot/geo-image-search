import Foundation

// One tool call the model wants to make — id ties it to the tool-role
// response message OpenAI expects back.
struct LLMToolCall: Sendable, Equatable {
    let id: String
    let name: String
    let argumentsJSON: String
}

// Either the model produced a final answer, or it wants to call tools.
enum LLMTurn: Sendable, Equatable {
    case message(String)
    case toolCalls([LLMToolCall])
}

struct LLMMessage: Sendable, Equatable {
    enum Role: String, Sendable {
        case system, user, assistant, tool
    }

    let role: Role
    let content: String?
    let toolCallID: String?       // set on role == .tool
    let toolCalls: [LLMToolCall]? // set on role == .assistant when it made tool calls

    static func system(_ content: String) -> LLMMessage {
        LLMMessage(role: .system, content: content, toolCallID: nil, toolCalls: nil)
    }

    static func user(_ content: String) -> LLMMessage {
        LLMMessage(role: .user, content: content, toolCallID: nil, toolCalls: nil)
    }

    static func assistant(content: String?, toolCalls: [LLMToolCall]?) -> LLMMessage {
        LLMMessage(role: .assistant, content: content, toolCallID: nil, toolCalls: toolCalls)
    }

    static func toolResult(callID: String, content: String) -> LLMMessage {
        LLMMessage(role: .tool, content: content, toolCallID: callID, toolCalls: nil)
    }
}

// So PhotoQueryAgent is testable without a real network call.
protocol LLMClient: Sendable {
    func send(messages: [LLMMessage], tools: [OpenAITool]) async throws -> LLMTurn
}

enum AgentConfigurationError: Error {
    case missingAPIKey
}

enum OpenAIClientError: Error {
    case decodingFailed
    case noChoiceReturned
    case unexpectedResponse(status: Int, body: String)
}

// Chat Completions API (not the newer Responses API — simpler request/
// response shape, well suited to this app's single-session desktop chat).
struct OpenAIClient: LLMClient, APIKeyValidating, Sendable {
    private let apiKeyProvider: @Sendable () throws -> String
    private let model: String
    private let session: URLSession
    private let baseURL: URL
    private let retryDelaying: any RetryDelaying

    init(
        apiKeyProvider: @escaping @Sendable () throws -> String,
        model: String = "gpt-4o-mini",
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        retryDelaying: any RetryDelaying = TaskSleepDelaying()
    ) {
        self.apiKeyProvider = apiKeyProvider
        self.model = model
        self.session = session
        self.baseURL = baseURL
        self.retryDelaying = retryDelaying
    }

    // Every call goes through RetryExecutor with LLMRetryPolicy (merged from
    // error-handling) — only plain AppError cases are retried, so failure
    // paths below must throw AppError directly, not a wrapping type.
    // retryDelaying is injectable (defaults to real Task.sleep) so tests can
    // exercise retry-exhaustion paths without waiting through real backoff.
    func send(messages: [LLMMessage], tools: [OpenAITool]) async throws -> LLMTurn {
        try await RetryExecutor.run(policy: LLMRetryPolicy(), delaying: retryDelaying) {
            try await performChatCompletion(messages: messages, tools: tools)
        }
    }

    private func performChatCompletion(messages: [LLMMessage], tools: [OpenAITool]) async throws -> LLMTurn {
        let apiKey = try apiKeyProvider()
        let body = ChatCompletionRequest(
            model: model,
            messages: messages.map(WireMessage.init),
            tools: tools,
            toolChoice: "auto"
        )

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            // Transport-layer failure (offline, DNS, timeout) — treated the
            // same as a server-side timeout so it rides LLMRetryPolicy's
            // backoff rather than failing the turn outright.
            throw AppError.llmTimeout
        }

        guard let http = response as? HTTPURLResponse else { throw AppError.llmTimeout }

        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw AppError.llmInvalidAPIKey
        case 429:
            // Both plain rate-limiting and quota exhaustion arrive as 429;
            // AppError has no dedicated quota case (locked by CONTRACT.md),
            // so both map here. Distinguishing them is APIKeyManager.validate's
            // job during key entry, not this mid-conversation path.
            throw AppError.llmRateLimited
        case 500...599:
            throw AppError.llmTimeout
        default:
            throw OpenAIClientError.unexpectedResponse(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        guard let decoded = try? JSONDecoder().decode(ChatCompletionResponse.self, from: data) else {
            throw OpenAIClientError.decodingFailed
        }
        guard let choice = decoded.choices.first else {
            throw OpenAIClientError.noChoiceReturned
        }

        if let toolCalls = choice.message.toolCalls, !toolCalls.isEmpty {
            return .toolCalls(toolCalls.map { LLMToolCall(id: $0.id, name: $0.function.name, argumentsJSON: $0.function.arguments) })
        }
        return .message(choice.message.content ?? "")
    }

    // Deliberately not routed through RetryExecutor/LLMRetryPolicy — key
    // entry wants immediate feedback, not up to 5 attempts over ~2 minutes
    // of backoff. Distinguishes invalid-key from quota-exhausted (both HTTP
    // 429 mid-conversation collapse to the same AppError case above, but
    // during validation the response body's error.code disambiguates them).
    func validate(apiKey: String) async throws -> APIKeyState {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw OpenAIClientError.unexpectedResponse(status: -1, body: "")
        }

        switch http.statusCode {
        case 200..<300:
            return .valid
        case 401:
            return .invalid
        case 429:
            if let errorBody = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
               errorBody.error.code == "insufficient_quota" {
                return .quotaExhausted
            }
            // A 429 without that code is an ambiguous transient rate limit,
            // not a confirmed-bad key — surface as a failure to validate
            // right now rather than falsely reporting .invalid.
            throw OpenAIClientError.unexpectedResponse(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        default:
            throw OpenAIClientError.unexpectedResponse(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }
}

// MARK: - Wire format

private struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [WireMessage]
    let tools: [OpenAITool]
    let toolChoice: String

    enum CodingKeys: String, CodingKey {
        case model, messages, tools
        case toolChoice = "tool_choice"
    }
}

private struct WireMessage: Codable {
    let role: String
    let content: String?
    let toolCallID: String?
    let toolCalls: [WireToolCall]?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    init(_ message: LLMMessage) {
        role = message.role.rawValue
        content = message.content
        toolCallID = message.toolCallID
        toolCalls = message.toolCalls?.map {
            WireToolCall(id: $0.id, type: "function", function: .init(name: $0.name, arguments: $0.argumentsJSON))
        }
    }
}

private struct WireToolCall: Codable {
    struct WireFunctionCall: Codable {
        let name: String
        let arguments: String
    }

    let id: String
    let type: String
    let function: WireFunctionCall
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String
            let content: String?
            let toolCalls: [WireToolCall]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
            }
        }

        let message: Message
    }

    let choices: [Choice]
}

private struct OpenAIErrorResponse: Decodable {
    struct ErrorBody: Decodable {
        let message: String
        let type: String?
        let code: String?
    }

    let error: ErrorBody
}
