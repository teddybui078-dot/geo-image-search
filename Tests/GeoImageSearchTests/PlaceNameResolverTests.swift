import Testing
import Foundation
import CoreLocation
@testable import GeoImageSearch

private struct StubGeocoding: Geocoding {
    let result: @Sendable (String) throws -> CLLocationCoordinate2D

    func geocodeAddressString(_ addressString: String) async throws -> CLLocationCoordinate2D {
        try result(addressString)
    }
}

private final class FlakyGeocoding: Geocoding, @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFailures: Int
    private let coordinate: CLLocationCoordinate2D

    init(failuresBeforeSuccess: Int, coordinate: CLLocationCoordinate2D) {
        self.remainingFailures = failuresBeforeSuccess
        self.coordinate = coordinate
    }

    func geocodeAddressString(_ addressString: String) async throws -> CLLocationCoordinate2D {
        let shouldFail = lock.withLock {
            let willFail = remainingFailures > 0
            if willFail { remainingFailures -= 1 }
            return willFail
        }

        if shouldFail {
            throw AppError.geocodingFailed(underlying: CLError(.network))
        }
        return coordinate
    }
}

@Suite struct PlaceNameResolverTests {
    @Test func resolvesToCoordinateOnSuccess() async throws {
        let coordinate = CLLocationCoordinate2D(latitude: 37.9838, longitude: 23.7275)
        let resolver = PlaceNameResolver(geocoding: StubGeocoding(result: { _ in coordinate }), retryDelaying: NoDelay())

        let result = try await resolver.resolve(placeName: "Athens")

        #expect(result.latitude == 37.9838)
        #expect(result.longitude == 23.7275)
    }

    @Test func retriesTransientFailuresBeforeSucceeding() async throws {
        let coordinate = CLLocationCoordinate2D(latitude: 1, longitude: 2)
        let geocoding = FlakyGeocoding(failuresBeforeSuccess: 2, coordinate: coordinate)
        let resolver = PlaceNameResolver(geocoding: geocoding, retryDelaying: NoDelay())

        let result = try await resolver.resolve(placeName: "Somewhere")

        #expect(result.latitude == 1)
        #expect(result.longitude == 2)
    }

    @Test func exhaustsRetriesAndThrowsOnPersistentFailure() async throws {
        let resolver = PlaceNameResolver(
            geocoding: StubGeocoding(result: { _ in throw AppError.geocodingFailed(underlying: CLError(.geocodeFoundNoResult)) }),
            retryDelaying: NoDelay()
        )

        do {
            _ = try await resolver.resolve(placeName: "Nowhereplace123")
            Issue.record("expected resolve to throw")
        } catch AppError.geocodingFailed {
            // expected
        } catch {
            Issue.record("expected .geocodingFailed, got \(error)")
        }
    }

    @Test func nonAppErrorPropagatesWithoutRetry() async throws {
        struct OtherError: Error {}
        let resolver = PlaceNameResolver(geocoding: StubGeocoding(result: { _ in throw OtherError() }), retryDelaying: NoDelay())

        await #expect(throws: OtherError.self) {
            _ = try await resolver.resolve(placeName: "Athens")
        }
    }
}
