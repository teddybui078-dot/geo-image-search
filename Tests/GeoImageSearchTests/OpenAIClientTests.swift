import Testing
import Foundation
@testable import GeoImageSearch

// Intercepts every request at the URLProtocol layer so these tests never hit
// the real network — StubURLProtocol.handler is set per-test and consulted
// for each request.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data)) = { _ in (200, Data()) }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, data) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// So retry-exhaustion tests don't wait through LLMRetryPolicy's real backoff.
struct NoDelay: RetryDelaying {
    func delay(_ duration: TimeInterval) async throws {}
}

final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }

    var current: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

enum OpenAIClientTestSupport {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func makeClient(session: URLSession, apiKey: String = "sk-test") -> OpenAIClient {
        OpenAIClient(apiKeyProvider: { apiKey }, session: session, retryDelaying: NoDelay())
    }

    static func assistantMessageJSON(content: String) -> Data {
        Data(#"{"choices": [{"message": {"role": "assistant", "content": "\#(content)"}}]}"#.utf8)
    }

    static func toolCallJSON(id: String, name: String, arguments: String) -> Data {
        let escapedArgs = arguments.replacingOccurrences(of: "\"", with: "\\\"")
        return Data(#"{"choices": [{"message": {"role": "assistant", "content": null, "tool_calls": [{"id": "\#(id)", "type": "function", "function": {"name": "\#(name)", "arguments": "\#(escapedArgs)"}}]}}]}"#.utf8)
    }
}

// .serialized: every test in this suite drives the same static
// StubURLProtocol.handler — Swift Testing runs tests concurrently by
// default, and two tests racing to set/read that shared handler would
// cross-contaminate each other's stubbed responses.
@Suite(.serialized) struct OpenAIClientTests {
    @Test func returnsMessageOnPlainAssistantReply() async throws {
        StubURLProtocol.handler = { _ in (200, OpenAIClientTestSupport.assistantMessageJSON(content: "hello")) }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        let turn = try await client.send(messages: [.user("hi")], tools: [])

        #expect(turn == .message("hello"))
    }

    @Test func returnsToolCallsWhenModelRequestsThem() async throws {
        StubURLProtocol.handler = { _ in
            (200, OpenAIClientTestSupport.toolCallJSON(id: "call_1", name: "query_by_location", arguments: #"{"placeName":"Athens"}"#))
        }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        let turn = try await client.send(messages: [.user("Athens photos")], tools: ToolSchemas.all)

        guard case .toolCalls(let calls) = turn else {
            Issue.record("expected tool calls, got \(turn)")
            return
        }
        #expect(calls == [LLMToolCall(id: "call_1", name: "query_by_location", argumentsJSON: #"{"placeName":"Athens"}"#)])
    }

    @Test func throws401AsInvalidAPIKey() async throws {
        StubURLProtocol.handler = { _ in (401, Data()) }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            Issue.record("expected send to throw")
        } catch AppError.llmInvalidAPIKey {
            // expected
        } catch {
            Issue.record("expected .llmInvalidAPIKey, got \(error)")
        }
    }

    @Test func throws429AsRateLimitedAfterExhaustingRetries() async throws {
        let counter = RequestCounter()
        StubURLProtocol.handler = { _ in
            counter.increment()
            return (429, Data())
        }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            Issue.record("expected send to throw")
        } catch AppError.llmRateLimited {
            // expected
        } catch {
            Issue.record("expected .llmRateLimited, got \(error)")
        }
        #expect(counter.current == LLMRetryPolicy().maxAttempts)
    }

    @Test func throws500AsLLMTimeout() async throws {
        StubURLProtocol.handler = { _ in (500, Data()) }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        do {
            _ = try await client.send(messages: [.user("hi")], tools: [])
            Issue.record("expected send to throw")
        } catch AppError.llmTimeout {
            // expected
        } catch {
            Issue.record("expected .llmTimeout, got \(error)")
        }
    }

    @Test func missingAPIKeyPropagatesWithoutNetworkCall() async throws {
        let counter = RequestCounter()
        StubURLProtocol.handler = { _ in counter.increment(); return (200, Data()) }
        let client = OpenAIClient(
            apiKeyProvider: { throw AgentConfigurationError.missingAPIKey },
            session: OpenAIClientTestSupport.makeSession(),
            retryDelaying: NoDelay()
        )

        await #expect(throws: AgentConfigurationError.self) {
            _ = try await client.send(messages: [.user("hi")], tools: [])
        }
        #expect(counter.current == 0)
    }

    @Test func validKeyReturnsValid() async throws {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        #expect(try await client.validate(apiKey: "sk-test") == .valid)
    }

    @Test func unauthorizedReturnsInvalid() async throws {
        StubURLProtocol.handler = { _ in (401, Data()) }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        #expect(try await client.validate(apiKey: "sk-bad") == .invalid)
    }

    @Test func insufficientQuotaReturnsQuotaExhausted() async throws {
        StubURLProtocol.handler = { _ in
            (429, Data(#"{"error": {"message": "You exceeded your quota", "type": "insufficient_quota", "code": "insufficient_quota"}}"#.utf8))
        }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        #expect(try await client.validate(apiKey: "sk-test") == .quotaExhausted)
    }

    @Test func ambiguousRateLimitDuringValidationThrowsRatherThanClaimingInvalid() async throws {
        StubURLProtocol.handler = { _ in
            (429, Data(#"{"error": {"message": "Rate limited", "type": "rate_limit_exceeded", "code": "rate_limit_exceeded"}}"#.utf8))
        }
        let client = OpenAIClientTestSupport.makeClient(session: OpenAIClientTestSupport.makeSession())

        await #expect(throws: (any Error).self) {
            _ = try await client.validate(apiKey: "sk-test")
        }
    }
}
