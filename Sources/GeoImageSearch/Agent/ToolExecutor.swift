import Foundation

struct ToolExecutionResult: Sendable {
    let assets: [PhotoAsset]  // full set, for GlobeUpdating — never truncated
    let summary: String       // fed back to the model as the tool-role message content
}

enum ToolExecutionError: Error {
    case unknownTool(String)
    case invalidArguments(tool: String, underlying: Error)
}

// Routes a decoded tool call from the model to PhotoQuery, translating
// results into a compact summary the model reasons over plus the full asset
// list the chat UI hands to GlobeUpdating.
struct ToolExecutor: Sendable {
    // Deliberately unscoped placeholders — TODOS.md item 2 defers
    // cluster_trips' real definition of a "trip" (stop duration, travel-gap
    // threshold, timezone handling) until real ingested data exists to
    // calibrate against. Same "deliberately simple v1" spirit as
    // SQLitePhotoQuery.clusterTrips' own implementation.
    static let defaultMinStopDuration: TimeInterval = 60 * 60 * 24      // 1 day
    static let defaultMaxTravelGap: TimeInterval = 60 * 60 * 24 * 2     // 2 days

    // PhotoQuery itself isn't declared Sendable (CONTRACT.md's locked
    // protocol shape) — combined here with Sendable at the point of use
    // instead, since every real conformer (SQLitePhotoQuery) already is one.
    private let photoQuery: any PhotoQuery & Sendable
    private let placeNameResolver: any PlaceNameResolving

    init(photoQuery: any PhotoQuery & Sendable, placeNameResolver: any PlaceNameResolving) {
        self.photoQuery = photoQuery
        self.placeNameResolver = placeNameResolver
    }

    func execute(toolCall: LLMToolCall) async throws -> ToolExecutionResult {
        let argumentsData = Data(toolCall.argumentsJSON.utf8)
        switch toolCall.name {
        case "query_by_location":
            let args = try decode(QueryByLocationArgs.self, from: argumentsData, tool: toolCall.name)
            return try await executeQueryByLocation(args)
        case "query_by_date_range":
            let args = try decode(QueryByDateRangeArgs.self, from: argumentsData, tool: toolCall.name)
            return try await executeQueryByDateRange(args)
        case "semantic_search":
            let args = try decode(SemanticSearchArgs.self, from: argumentsData, tool: toolCall.name)
            return executeSemanticSearch(args)
        case "cluster_trips":
            let args = try decode(ClusterTripsArgs.self, from: argumentsData, tool: toolCall.name)
            return try await executeClusterTrips(args)
        default:
            throw ToolExecutionError.unknownTool(toolCall.name)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, tool: String) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw ToolExecutionError.invalidArguments(tool: tool, underlying: error)
        }
    }

    private func executeQueryByLocation(_ args: QueryByLocationArgs) async throws -> ToolExecutionResult {
        let coordinate = try await placeNameResolver.resolve(placeName: args.placeName)
        let assets = try await photoQuery.byLocation(latitude: coordinate.latitude, longitude: coordinate.longitude, radiusKm: args.radiusKm)
        let summary = assets.isEmpty
            ? "No photos found within \(Int(args.radiusKm))km of '\(args.placeName)'."
            : "Found \(assets.count) photo(s) within \(Int(args.radiusKm))km of '\(args.placeName)'."
        return ToolExecutionResult(assets: assets, summary: summary)
    }

    private func executeQueryByDateRange(_ args: QueryByDateRangeArgs) async throws -> ToolExecutionResult {
        // args.end is parsed as midnight UTC on the given day — extend to
        // the end of that day so the whole day is inclusive, matching what
        // "through June 30th" means to a user asking the question.
        let inclusiveEnd = args.end.addingTimeInterval(24 * 60 * 60 - 1)
        let assets = try await photoQuery.byDateRange(start: args.start, end: inclusiveEnd)
        let startLabel = ToolSchemas.dateOnlyFormatter.string(from: args.start)
        let endLabel = ToolSchemas.dateOnlyFormatter.string(from: args.end)
        let summary = assets.isEmpty
            ? "No photos found between \(startLabel) and \(endLabel)."
            : "Found \(assets.count) photo(s) between \(startLabel) and \(endLabel)."
        return ToolExecutionResult(assets: assets, summary: summary)
    }

    // Stubbed: embedding-pipeline hasn't shipped real vectors yet
    // (CONTRACT.md's parallelization guide) — returns no results with an
    // honest explanation rather than fabricated matches.
    private func executeSemanticSearch(_ args: SemanticSearchArgs) -> ToolExecutionResult {
        ToolExecutionResult(
            assets: [],
            summary: "Semantic search isn't available yet — no photo embeddings have been generated. Try a location or date-based question instead."
        )
    }

    private func executeClusterTrips(_ args: ClusterTripsArgs) async throws -> ToolExecutionResult {
        let clusters = try await photoQuery.clusterTrips(
            minStopDuration: Self.defaultMinStopDuration,
            maxTravelGap: Self.defaultMaxTravelGap
        )
        let filtered: [TripCluster]
        if let placeName = args.placeName {
            filtered = clusters.filter { $0.placeName?.localizedCaseInsensitiveContains(placeName) ?? false }
        } else {
            filtered = clusters
        }

        guard !filtered.isEmpty, let start = filtered.map(\.startDate).min(), let end = filtered.map(\.endDate).max() else {
            let suffix = args.placeName.map { " matching '\($0)'" } ?? ""
            return ToolExecutionResult(assets: [], summary: "No trips found\(suffix).")
        }

        // clusterTrips only returns centroid + assetIDs, not full PhotoAsset
        // records — reuse byDateRange (already exposed) over the filtered
        // clusters' combined span rather than adding a new PhotoQuery method.
        let assetIDs = Set(filtered.flatMap(\.assetIDs))
        let candidates = try await photoQuery.byDateRange(start: start, end: end)
        let assets = candidates.filter { assetIDs.contains($0.id) }

        let tripDescriptions = filtered.map { cluster -> String in
            let place = cluster.placeName ?? "an unnamed location"
            let startLabel = ToolSchemas.dateOnlyFormatter.string(from: cluster.startDate)
            let endLabel = ToolSchemas.dateOnlyFormatter.string(from: cluster.endDate)
            return "\(place) (\(startLabel) to \(endLabel))"
        }.joined(separator: ", ")

        return ToolExecutionResult(
            assets: assets,
            summary: "Found \(filtered.count) trip(s) covering \(assets.count) photo(s): \(tripDescriptions)"
        )
    }
}
