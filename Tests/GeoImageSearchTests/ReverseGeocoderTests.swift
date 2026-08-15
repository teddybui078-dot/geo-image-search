import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct ReverseGeocoderTests {
    @Test func cachesWithinTheSameBucket() async throws {
        let lookup = FakeGeocodeLookup(results: [.success("Paris, France")])
        let geocoder = ReverseGeocoder(lookup: lookup, minimumCallInterval: 0, delaying: GeocodingDelaySpy())

        let first = try await geocoder.placeName(latitude: 48.8566, longitude: 2.3522)
        // Nudge by less than the ~1km bucket width — same bucket key.
        let second = try await geocoder.placeName(latitude: 48.85661, longitude: 2.35221)

        #expect(first == "Paris, France")
        #expect(second == "Paris, France")
        #expect(await lookup.callCount == 1)
    }

    @Test func distinctBucketsBothCallTheLookup() async throws {
        let lookup = FakeGeocodeLookup(results: [.success("Paris, France"), .success("Berlin, Germany")])
        let geocoder = ReverseGeocoder(lookup: lookup, minimumCallInterval: 0, delaying: GeocodingDelaySpy())

        _ = try await geocoder.placeName(latitude: 48.8566, longitude: 2.3522)
        _ = try await geocoder.placeName(latitude: 52.5200, longitude: 13.4050)

        #expect(await lookup.callCount == 2)
    }

    @Test func retriesRetryableFailureThenSucceeds() async throws {
        let lookup = FakeGeocodeLookup(results: [.failure(AppError.geocodingRateLimited), .success("Rome, Italy")])
        let delaying = GeocodingDelaySpy()
        let geocoder = ReverseGeocoder(lookup: lookup, minimumCallInterval: 0, delaying: delaying)

        let result = try await geocoder.placeName(latitude: 41.9028, longitude: 12.4964)

        #expect(result == "Rome, Italy")
        #expect(await lookup.callCount == 2)
        #expect(delaying.delays.count == 1) // one retry backoff
    }

    @Test func exhaustsRetriesAndThrows() async throws {
        // GeocodingRetryPolicy.maxAttempts == 4.
        let lookup = FakeGeocodeLookup(results: Array(repeating: .failure(AppError.geocodingFailed(underlying: TestError())), count: 4))
        let geocoder = ReverseGeocoder(lookup: lookup, minimumCallInterval: 0, delaying: GeocodingDelaySpy())

        await #expect(throws: AppError.self) {
            try await geocoder.placeName(latitude: 0, longitude: 0)
        }
        #expect(await lookup.callCount == 4)
    }

    @Test func throttlesBetweenDistinctBucketCalls() async throws {
        let lookup = FakeGeocodeLookup(results: [.success("A"), .success("B")])
        let delaying = GeocodingDelaySpy()
        let geocoder = ReverseGeocoder(lookup: lookup, minimumCallInterval: 5.0, delaying: delaying)

        _ = try await geocoder.placeName(latitude: 0, longitude: 0)
        _ = try await geocoder.placeName(latitude: 10, longitude: 10)

        // First call never throttles (no prior call); second call is a
        // distinct bucket, so it must wait out the minimum interval.
        #expect(delaying.delays.count == 1)
        #expect(delaying.delays[0] > 0)
        #expect(delaying.delays[0] <= 5.0)
    }
}

private struct TestError: Error {}
