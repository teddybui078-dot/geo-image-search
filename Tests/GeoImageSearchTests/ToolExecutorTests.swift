import Testing
import Foundation
@testable import GeoImageSearch

private struct StubPlaceNameResolving: PlaceNameResolving {
    let result: @Sendable (String) throws -> (latitude: Double, longitude: Double)
    func resolve(placeName: String) async throws -> (latitude: Double, longitude: Double) {
        try result(placeName)
    }
}

private func toolCall(name: String, argsJSON: String) -> LLMToolCall {
    LLMToolCall(id: "call_1", name: name, argumentsJSON: argsJSON)
}

@Suite struct ToolExecutorTests {
    @Test func queryByLocationResolvesPlaceThenQueriesPhotoQuery() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "near", latitude: 37.98, longitude: 23.73),
            PhotoAssetFixtures.makeAsset(id: "far", latitude: 10, longitude: 10)
        ])
        let resolver = StubPlaceNameResolving(result: { _ in (37.9838, 23.7275) })
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: resolver)

        let result = try await executor.execute(toolCall: toolCall(name: "query_by_location", argsJSON: #"{"placeName":"Athens","radiusKm":50}"#))

        #expect(result.assets.map(\.id) == ["near"])
        #expect(result.summary.contains("1 photo"))
        #expect(result.summary.contains("Athens"))
    }

    @Test func queryByLocationNoResultsProducesHonestSummary() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let resolver = StubPlaceNameResolving(result: { _ in (0, 0) })
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: resolver)

        let result = try await executor.execute(toolCall: toolCall(name: "query_by_location", argsJSON: #"{"placeName":"Nowhere"}"#))

        #expect(result.assets.isEmpty)
        #expect(result.summary.contains("No photos found"))
    }

    @Test func queryByLocationPropagatesResolverFailure() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let resolver = StubPlaceNameResolving(result: { _ in throw AppError.geocodingFailed(underlying: URLError(.badServerResponse)) })
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: resolver)

        await #expect(throws: AppError.self) {
            _ = try await executor.execute(toolCall: toolCall(name: "query_by_location", argsJSON: #"{"placeName":"Nowhere"}"#))
        }
    }

    @Test func queryByDateRangeIsInclusiveOfEndDate() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        // 2022-06-30 23:30 UTC — inside the end date but after midnight,
        // exercising the "extend to end of day" inclusive-range behavior.
        let lateOnEndDate = ToolSchemas.dateOnlyFormatter.date(from: "2022-06-30")!.addingTimeInterval(23.5 * 60 * 60)
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "late-on-end-date", capturedAt: lateOnEndDate)])
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        let result = try await executor.execute(toolCall: toolCall(name: "query_by_date_range", argsJSON: #"{"start":"2022-06-01","end":"2022-06-30"}"#))

        #expect(result.assets.map(\.id) == ["late-on-end-date"])
    }

    @Test func queryByDateRangeNoResultsProducesHonestSummary() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        let result = try await executor.execute(toolCall: toolCall(name: "query_by_date_range", argsJSON: #"{"start":"2022-06-01","end":"2022-06-30"}"#))

        #expect(result.assets.isEmpty)
        #expect(result.summary.contains("No photos found"))
    }

    @Test func semanticSearchReturnsEmptyWithExplanation() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        let result = try await executor.execute(toolCall: toolCall(name: "semantic_search", argsJSON: #"{"query":"sunset on a beach"}"#))

        #expect(result.assets.isEmpty)
        #expect(result.summary.contains("not available") || result.summary.contains("isn't available"))
    }

    @Test func clusterTripsReturnsMatchingClusterAssets() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        // ToolExecutor's default minStopDuration is 1 day (placeholder,
        // TODOS.md item 2) — span the two photos > 1 day apart so the
        // cluster survives that threshold, but well under the 2-day
        // maxTravelGap so they still land in the same trip.
        try await store.upsert([
            PhotoAssetFixtures.makeAsset(id: "trip-1", latitude: 37.98, longitude: 23.73, capturedAt: base, placeName: "Athens, Greece"),
            PhotoAssetFixtures.makeAsset(id: "trip-2", latitude: 37.98, longitude: 23.73, capturedAt: base.addingTimeInterval(90_000), placeName: "Athens, Greece")
        ])
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        let result = try await executor.execute(toolCall: toolCall(name: "cluster_trips", argsJSON: #"{"placeName":"Greece"}"#))

        #expect(Set(result.assets.map(\.id)) == ["trip-1", "trip-2"])
        #expect(result.summary.contains("1 trip"))
    }

    @Test func clusterTripsWithNoMatchingPlaceProducesHonestSummary() async throws {
        let (store, query) = try await TestDatabase.makeStoreAndQuery()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "solo", placeName: "Tokyo, Japan")])
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        let result = try await executor.execute(toolCall: toolCall(name: "cluster_trips", argsJSON: #"{"placeName":"Antarctica"}"#))

        #expect(result.assets.isEmpty)
        #expect(result.summary.contains("No trips found"))
    }

    @Test func unknownToolNameThrows() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        await #expect(throws: ToolExecutionError.self) {
            _ = try await executor.execute(toolCall: toolCall(name: "not_a_real_tool", argsJSON: "{}"))
        }
    }

    @Test func malformedArgumentsThrowInvalidArguments() async throws {
        let (_, query) = try await TestDatabase.makeStoreAndQuery()
        let executor = ToolExecutor(photoQuery: query, placeNameResolver: StubPlaceNameResolving(result: { _ in (0, 0) }))

        await #expect(throws: ToolExecutionError.self) {
            _ = try await executor.execute(toolCall: toolCall(name: "query_by_location", argsJSON: "{}"))
        }
    }
}
