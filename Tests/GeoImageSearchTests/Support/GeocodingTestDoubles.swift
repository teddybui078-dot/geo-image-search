import Foundation
@testable import GeoImageSearch

final class GeocodingDelaySpy: RetryDelaying, @unchecked Sendable {
    private(set) var delays: [TimeInterval] = []

    func delay(_ duration: TimeInterval) async throws {
        delays.append(duration)
    }
}

// Actor, not a class: placeName is called from ReverseGeocoder's actor-
// isolated context, and the queued-results/callCount bookkeeping needs the
// same concurrency-safety guarantee a real GeocodeLookup would have.
actor FakeGeocodeLookup: GeocodeLookup {
    private var results: [Result<String?, Error>]
    private(set) var callCount = 0

    init(results: [Result<String?, Error>]) {
        self.results = results
    }

    func placeName(latitude: Double, longitude: Double) async throws -> String? {
        callCount += 1
        guard !results.isEmpty else { return nil }
        return try results.removeFirst().get()
    }
}
