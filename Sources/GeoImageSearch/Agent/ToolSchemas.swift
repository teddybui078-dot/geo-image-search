import Foundation

// A minimal JSON-Schema-shaped Codable model — just enough to express the
// four flat tool schemas below, not a general JSON Schema library.
struct JSONSchemaProperty: Codable, Sendable {
    enum ValueType: String, Codable, Sendable {
        case string, number, integer
    }

    let type: ValueType
    let description: String?
    let defaultValue: JSONSchemaValue?

    enum CodingKeys: String, CodingKey {
        case type, description
        case defaultValue = "default"
    }

    init(type: ValueType, description: String? = nil, defaultValue: JSONSchemaValue? = nil) {
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
    }
}

// Only string/number/integer defaults are needed by the four schemas below —
// deliberately not a general JSON value type.
enum JSONSchemaValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case integer(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .integer(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            self = .number(doubleValue)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

struct JSONSchemaObject: Codable, Sendable {
    let type = "object"
    let properties: [String: JSONSchemaProperty]
    let required: [String]?

    enum CodingKeys: String, CodingKey { case type, properties, required }

    init(properties: [String: JSONSchemaProperty], required: [String]? = nil) {
        self.properties = properties
        self.required = required
    }
}

struct OpenAIFunctionDefinition: Codable, Sendable {
    let name: String
    let description: String
    let parameters: JSONSchemaObject
}

// OpenAI Chat Completions tool-calling shape: {"type": "function", "function": {...}}.
struct OpenAITool: Codable, Sendable {
    let type = "function"
    let function: OpenAIFunctionDefinition

    enum CodingKeys: String, CodingKey { case type, function }

    init(function: OpenAIFunctionDefinition) {
        self.function = function
    }
}

// Next Step 6 / TODOS.md item 1 — explicit param schemas for the four agent
// tools, matching PhotoQuery 1:1 (allActivePhotosWithLocation has no tool —
// it's map-only, per CONTRACT.md). This is the working draft CONTRACT.md
// flags as owned/refinable by this feature: cluster_trips deliberately
// exposes no stop-duration/travel-gap params (TODOS.md item 2 defers real
// scoping until real ingested data exists to calibrate against).
enum ToolSchemas {
    // Pure date, not date-time — the model is expected to resolve relative
    // phrasing ("last summer") into concrete YYYY-MM-DD bounds itself,
    // grounded by the current date in PhotoQueryAgent's system prompt.
    static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }()

    static let queryByLocation = OpenAITool(function: OpenAIFunctionDefinition(
        name: "query_by_location",
        description: "Find photos taken near a named place (city, country, landmark, etc).",
        parameters: JSONSchemaObject(
            properties: [
                "placeName": JSONSchemaProperty(
                    type: .string,
                    description: "e.g. 'Athens', 'Greece' — resolved to coordinates via live geocoding"
                ),
                "radiusKm": JSONSchemaProperty(
                    type: .number,
                    description: "Search radius in kilometers around the resolved place",
                    defaultValue: .number(50)
                )
            ],
            required: ["placeName"]
        )
    ))

    static let queryByDateRange = OpenAITool(function: OpenAIFunctionDefinition(
        name: "query_by_date_range",
        description: "Find photos taken within a date range. Resolve relative phrasing (\"last summer\", \"in 2022\") to concrete YYYY-MM-DD dates before calling.",
        parameters: JSONSchemaObject(
            properties: [
                "start": JSONSchemaProperty(type: .string, description: "Start date, YYYY-MM-DD, inclusive"),
                "end": JSONSchemaProperty(type: .string, description: "End date, YYYY-MM-DD, inclusive")
            ],
            required: ["start", "end"]
        )
    ))

    static let semanticSearch = OpenAITool(function: OpenAIFunctionDefinition(
        name: "semantic_search",
        description: "Find photos matching a free-text visual description, e.g. 'sunset on a beach'. Not yet backed by real embeddings — currently returns no results.",
        parameters: JSONSchemaObject(
            properties: [
                "query": JSONSchemaProperty(type: .string, description: "free-text description, e.g. 'sunset on a beach'"),
                "limit": JSONSchemaProperty(type: .integer, description: "maximum number of results", defaultValue: .integer(20))
            ],
            required: ["query"]
        )
    ))

    static let clusterTrips = OpenAITool(function: OpenAIFunctionDefinition(
        name: "cluster_trips",
        description: "Group photos into trips (contiguous stretches of time+location) to answer questions like 'my Greece trip'.",
        parameters: JSONSchemaObject(
            properties: [
                "placeName": JSONSchemaProperty(type: .string, description: "optional filter, e.g. 'Greece' — matches a trip's most common place name")
            ],
            required: nil
        )
    ))

    static let all: [OpenAITool] = [queryByLocation, queryByDateRange, semanticSearch, clusterTrips]
}

// Decoded from a tool call's JSON argument string (OpenAI sends arguments
// as a JSON-encoded string, not a nested object).
struct QueryByLocationArgs: Decodable, Sendable {
    let placeName: String
    let radiusKm: Double

    private enum CodingKeys: String, CodingKey { case placeName, radiusKm }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placeName = try container.decode(String.self, forKey: .placeName)
        radiusKm = try container.decodeIfPresent(Double.self, forKey: .radiusKm) ?? 50
    }
}

struct QueryByDateRangeArgs: Decodable, Sendable {
    let start: Date
    let end: Date

    private enum CodingKeys: String, CodingKey { case start, end }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let startString = try container.decode(String.self, forKey: .start)
        let endString = try container.decode(String.self, forKey: .end)
        guard let start = ToolSchemas.dateOnlyFormatter.date(from: startString) else {
            throw DecodingError.dataCorruptedError(forKey: .start, in: container, debugDescription: "Expected YYYY-MM-DD date, got '\(startString)'")
        }
        guard let end = ToolSchemas.dateOnlyFormatter.date(from: endString) else {
            throw DecodingError.dataCorruptedError(forKey: .end, in: container, debugDescription: "Expected YYYY-MM-DD date, got '\(endString)'")
        }
        self.start = start
        self.end = end
    }
}

struct SemanticSearchArgs: Decodable, Sendable {
    let query: String
    let limit: Int

    private enum CodingKeys: String, CodingKey { case query, limit }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        limit = try container.decodeIfPresent(Int.self, forKey: .limit) ?? 20
    }
}

struct ClusterTripsArgs: Decodable, Sendable {
    let placeName: String?
}
