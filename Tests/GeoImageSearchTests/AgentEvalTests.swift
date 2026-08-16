import Testing
import Foundation
@testable import GeoImageSearch

// TODOS.md item 1 — hardened eval suite: fixed question -> expected tool
// (+ params, documented in eval/tool-selection.jsonl though not strictly
// asserted here — free-text param wording varies too much to assert
// reliably) + expected result set, covering ambiguous queries, no-result
// cases, and date-relative phrasing. Per DESIGN.md's Success Criteria this
// is run manually when the tool surface or prompts change, not scripted
// CI — this test makes real OpenAI calls, so it skips (not fails) unless
// OPENAI_API_KEY is set in the environment.
enum AgentEvalFixtures {
    // A fixed reference date so cluster_trips' gap math and any
    // non-relative eval cases behave identically no matter when the suite
    // actually runs; date-relative cases ("last summer") still resolve
    // against this instead of the real today.
    static let referenceDate = ISO8601DateFormatter().date(from: "2026-08-16T00:00:00Z")!

    static let libraryAssets: [PhotoAsset] = [
        PhotoAssetFixtures.makeAsset(
            id: "athens-2022", latitude: 37.9838, longitude: 23.7275,
            capturedAt: date("2022-06-15T10:00:00Z"), placeName: "Athens, Greece"
        ),
        // 24h after athens-2022 — exactly meets ToolExecutor's 1-day
        // minStopDuration placeholder, well under its 2-day maxTravelGap,
        // so both land in one cluster_trips "Greece" trip.
        PhotoAssetFixtures.makeAsset(
            id: "santorini-2022", latitude: 36.3932, longitude: 25.4615,
            capturedAt: date("2022-06-16T10:00:00Z"), placeName: "Santorini, Greece"
        ),
        PhotoAssetFixtures.makeAsset(
            id: "paris-2023", latitude: 48.8566, longitude: 2.3522,
            capturedAt: date("2023-03-10T10:00:00Z"), placeName: "Paris, France"
        ),
        PhotoAssetFixtures.makeAsset(
            id: "tokyo-2019a", latitude: 35.6762, longitude: 139.6503,
            capturedAt: date("2019-11-05T10:00:00Z"), placeName: "Tokyo, Japan"
        ),
        // ~26h after tokyo-2019a — same reasoning as santorini-2022 above.
        PhotoAssetFixtures.makeAsset(
            id: "tokyo-2019b", latitude: 35.6762, longitude: 139.6503,
            capturedAt: date("2019-11-06T12:00:00Z"), placeName: "Tokyo, Japan"
        ),
        PhotoAssetFixtures.makeAsset(
            id: "home-no-gps-2020", latitude: nil, longitude: nil,
            capturedAt: date("2020-01-10T10:00:00Z"), placeName: nil
        ),
        // Deliberately alone — no other photo within a day, so it can't
        // form a cluster_trips trip under the 1-day minStopDuration
        // placeholder. See tool-selection.jsonl's "no_result" case for it.
        PhotoAssetFixtures.makeAsset(
            id: "solo-nyc-2024", latitude: 40.7128, longitude: -74.0060,
            capturedAt: date("2024-07-04T10:00:00Z"), placeName: "New York, USA"
        )
    ]

    static func loadCases() throws -> [EvalCase] {
        let path = repoRoot().appendingPathComponent("eval/tool-selection.jsonl")
        let contents = try String(contentsOf: path, encoding: .utf8)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try contents
            .split(separator: "\n")
            .map { try decoder.decode(EvalCase.self, from: Data($0.utf8)) }
    }

    private static func date(_ iso8601: String) -> Date {
        ISO8601DateFormatter().date(from: iso8601)!
    }

    // #filePath is this file's own absolute path at compile time —
    // Tests/GeoImageSearchTests/AgentEvalTests.swift, three components
    // below the repo root.
    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

struct EvalCase: Decodable {
    let question: String
    let category: String
    let expectedTool: String?
    let acceptableTools: [String]?
    let expectedParams: [String: String]?
    let expectedAssetIds: [String]?
    let expectedResultKind: String
    let notes: String?

    var acceptableToolNames: [String] {
        acceptableTools ?? expectedTool.map { [$0] } ?? []
    }
}

@Suite struct AgentEvalTests {
    // Always runs (no API key needed) — catches a malformed jsonl line or a
    // typo'd expected_asset_ids reference before it silently no-ops inside
    // the API-key-gated suite below.
    @Test func evalFixturesParseAndReferenceKnownAssetIDs() throws {
        let cases = try AgentEvalFixtures.loadCases()
        #expect(!cases.isEmpty)

        let knownIDs = Set(AgentEvalFixtures.libraryAssets.map(\.id))
        let knownResultKinds: Set<String> = ["photo_set", "trip_set", "empty"]
        for evalCase in cases {
            for id in evalCase.expectedAssetIds ?? [] {
                if !knownIDs.contains(id) {
                    Issue.record("eval case '\(evalCase.question)' references unknown asset id '\(id)'")
                }
            }
            #expect(!evalCase.acceptableToolNames.isEmpty)
            #expect(knownResultKinds.contains(evalCase.expectedResultKind))
        }
    }

    @Test func toolSelectionEvalSuite() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            print("OPENAI_API_KEY not set — skipping the agent eval suite. Run manually with it set to exercise real tool-routing; see eval/README.md.")
            return
        }

        let cases = try AgentEvalFixtures.loadCases()
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert(AgentEvalFixtures.libraryAssets)

        let executor = ToolExecutor(photoQuery: query, placeNameResolver: PlaceNameResolver())
        let client = OpenAIClient(apiKeyProvider: { apiKey })
        let agent = PhotoQueryAgent(llmClient: client, toolExecutor: executor, currentDateProvider: { AgentEvalFixtures.referenceDate })

        var failures: [String] = []
        for evalCase in cases {
            let result = try await agent.ask(evalCase.question)
            let calledTools = result.updatedMessages.compactMap(\.toolCalls).flatMap { $0 }.map(\.name)

            let acceptable = evalCase.acceptableToolNames
            if !acceptable.isEmpty, !calledTools.contains(where: acceptable.contains) {
                failures.append("[\(evalCase.category)] '\(evalCase.question)': expected one of \(acceptable), got \(calledTools)")
            }

            if let expectedIDs = evalCase.expectedAssetIds {
                let actualIDs = Set(result.assets.map(\.id))
                if actualIDs != Set(expectedIDs) {
                    failures.append("[\(evalCase.category)] '\(evalCase.question)': expected assets \(expectedIDs.sorted()), got \(actualIDs.sorted())")
                }
            }

            print("[\(evalCase.category)] '\(evalCase.question)' -> tools=\(calledTools) assets=\(result.assets.map(\.id).sorted()) answer=\"\(result.responseText)\"")
        }

        for failure in failures {
            Issue.record("\(failure)")
        }
        #expect(failures.isEmpty)
    }
}
