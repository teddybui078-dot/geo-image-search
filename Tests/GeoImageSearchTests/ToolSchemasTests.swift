import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct ToolSchemasTests {
    @Test func allFourToolsPresentWithMatchingNames() {
        let names = ToolSchemas.all.map(\.function.name)
        #expect(names == ["query_by_location", "query_by_date_range", "semantic_search", "cluster_trips"])
    }

    @Test func queryByLocationEncodesExpectedShape() throws {
        let data = try JSONEncoder().encode(ToolSchemas.queryByLocation)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] as? String == "function")
        let function = json?["function"] as? [String: Any]
        #expect(function?["name"] as? String == "query_by_location")
        let parameters = function?["parameters"] as? [String: Any]
        #expect(parameters?["required"] as? [String] == ["placeName"])
        let properties = parameters?["properties"] as? [String: Any]
        #expect(properties?["placeName"] != nil)
        #expect(properties?["radiusKm"] != nil)
    }

    @Test func clusterTripsHasNoRequiredParams() {
        #expect(ToolSchemas.clusterTrips.function.parameters.required == nil)
    }

    @Test func queryByLocationArgsDefaultsRadiusKm() throws {
        let json = #"{"placeName": "Athens"}"#
        let args = try JSONDecoder().decode(QueryByLocationArgs.self, from: Data(json.utf8))
        #expect(args.placeName == "Athens")
        #expect(args.radiusKm == 50)
    }

    @Test func queryByLocationArgsHonorsExplicitRadiusKm() throws {
        let json = #"{"placeName": "Athens", "radiusKm": 10}"#
        let args = try JSONDecoder().decode(QueryByLocationArgs.self, from: Data(json.utf8))
        #expect(args.radiusKm == 10)
    }

    @Test func queryByDateRangeArgsParsesDateOnlyStrings() throws {
        let json = #"{"start": "2022-06-01", "end": "2022-06-30"}"#
        let args = try JSONDecoder().decode(QueryByDateRangeArgs.self, from: Data(json.utf8))
        #expect(ToolSchemas.dateOnlyFormatter.string(from: args.start) == "2022-06-01")
        #expect(ToolSchemas.dateOnlyFormatter.string(from: args.end) == "2022-06-30")
    }

    @Test func queryByDateRangeArgsRejectsMalformedDate() {
        let json = #"{"start": "not-a-date", "end": "2022-06-30"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(QueryByDateRangeArgs.self, from: Data(json.utf8))
        }
    }

    @Test func semanticSearchArgsDefaultsLimit() throws {
        let json = #"{"query": "sunset on a beach"}"#
        let args = try JSONDecoder().decode(SemanticSearchArgs.self, from: Data(json.utf8))
        #expect(args.query == "sunset on a beach")
        #expect(args.limit == 20)
    }

    @Test func clusterTripsArgsPlaceNameOptional() throws {
        let args = try JSONDecoder().decode(ClusterTripsArgs.self, from: Data("{}".utf8))
        #expect(args.placeName == nil)
    }
}
