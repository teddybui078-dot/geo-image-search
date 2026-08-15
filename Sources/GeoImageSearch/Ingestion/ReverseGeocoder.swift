import CoreLocation
import Foundation

// The raw CLGeocoder call, abstracted so ReverseGeocoder's caching/
// throttling/retry logic is testable without hitting the network.
protocol GeocodeLookup: Sendable {
    func placeName(latitude: Double, longitude: Double) async throws -> String?
}

// A fresh CLGeocoder per call, not a stored instance — CLGeocoder isn't
// Sendable, and creating one is documented as lightweight, so this avoids
// the whole "non-Sendable stored property" problem for free instead of
// reaching for @unchecked Sendable.
struct CLGeocoderLookup: GeocodeLookup {
    func placeName(latitude: Double, longitude: Double) async throws -> String? {
        do {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: latitude, longitude: longitude)
            )
            let parts = [placemarks.first?.locality, placemarks.first?.country].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        } catch let error as CLError where error.code == .network {
            // CLGeocoder throttling surfaces as a generic network-domain
            // error — Apple doesn't expose a distinct rate-limit code.
            // Treated as the rate-limit case so GeocodingRetryPolicy's
            // longer backoff applies instead of a plain-failure retry budget.
            throw AppError.geocodingRateLimited
        } catch {
            throw AppError.geocodingFailed(underlying: error)
        }
    }
}

protocol ReverseGeocoding: Sendable {
    func placeName(latitude: Double, longitude: Double) async throws -> String?
}

// Actor, not a struct: the in-memory bucket cache and last-call timestamp
// are mutable state shared across every call during one ingestion run, and
// actor isolation makes concurrent geocoding of a batch safe without a
// separate lock. Per DESIGN.md: "~1km bucketed + cached + throttled" — this
// is the one place all three live together.
//
// The cache is process-lifetime only (not persisted across relaunches):
// CONTRACT.md's schema has no separate geocode-cache table, and it doesn't
// need one — a photo's resolved place_name is already persisted on the
// photos row itself, so only new/changed assets (SyncPlanner's diff) ever
// need geocoding on a given run, and the in-memory cache is what collapses
// *those* calls when several are near each other in the same run.
actor ReverseGeocoder: ReverseGeocoding {
    private let lookup: any GeocodeLookup
    private let minimumCallInterval: TimeInterval
    private let delaying: any RetryDelaying
    private var cache: [String: String?] = [:]
    private var lastCallAt: Date?

    init(
        lookup: any GeocodeLookup = CLGeocoderLookup(),
        minimumCallInterval: TimeInterval = 1.0,
        delaying: any RetryDelaying = TaskSleepDelaying()
    ) {
        self.lookup = lookup
        self.minimumCallInterval = minimumCallInterval
        self.delaying = delaying
    }

    func placeName(latitude: Double, longitude: Double) async throws -> String? {
        let key = GeoBucket.key(latitude: latitude, longitude: longitude)
        if let cached = cache[key] {
            return cached
        }

        try await throttle()

        let resolved = try await RetryExecutor.run(policy: GeocodingRetryPolicy(), delaying: delaying) {
            try await self.lookup.placeName(latitude: latitude, longitude: longitude)
        }
        cache[key] = resolved
        return resolved
    }

    private func throttle() async throws {
        defer { lastCallAt = Date() }
        guard let lastCallAt else { return }
        let remaining = minimumCallInterval - Date().timeIntervalSince(lastCallAt)
        if remaining > 0 {
            try await delaying.delay(remaining)
        }
    }
}
