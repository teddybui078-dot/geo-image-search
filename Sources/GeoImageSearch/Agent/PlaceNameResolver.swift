import Foundation
import CoreLocation

// Wraps CLGeocoder's forward-geocoding behind a protocol so tests inject a
// fake instead of making real network geocoding calls.
protocol Geocoding: Sendable {
    func geocodeAddressString(_ addressString: String) async throws -> CLLocationCoordinate2D
}

struct SystemGeocoder: Geocoding {
    func geocodeAddressString(_ addressString: String) async throws -> CLLocationCoordinate2D {
        do {
            // A fresh CLGeocoder per call — CLGeocoder implicitly cancels an
            // in-flight request on the same instance when a new one starts,
            // which would race concurrent resolve() calls against each other.
            let placemarks = try await CLGeocoder().geocodeAddressString(addressString)
            guard let coordinate = placemarks.first?.location?.coordinate else {
                throw AppError.geocodingFailed(underlying: CLError(.geocodeFoundNoResult))
            }
            return coordinate
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.geocodingFailed(underlying: error)
        }
    }
}

// query_by_location's placeName -> coordinates step (live CLGeocoder only —
// no cached place_name lookup, since that column is empty until
// photo-icloud-extraction ships real reverse-geocoded data).
protocol PlaceNameResolving: Sendable {
    func resolve(placeName: String) async throws -> (latitude: Double, longitude: Double)
}

struct PlaceNameResolver: PlaceNameResolving {
    private let geocoding: any Geocoding
    private let retryDelaying: any RetryDelaying

    init(geocoding: any Geocoding = SystemGeocoder(), retryDelaying: any RetryDelaying = TaskSleepDelaying()) {
        self.geocoding = geocoding
        self.retryDelaying = retryDelaying
    }

    func resolve(placeName: String) async throws -> (latitude: Double, longitude: Double) {
        let coordinate = try await RetryExecutor.run(policy: GeocodingRetryPolicy(), delaying: retryDelaying) {
            try await geocoding.geocodeAddressString(placeName)
        }
        return (coordinate.latitude, coordinate.longitude)
    }
}
