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
// actor isolation makes concurrent geocoding of a batch memory-safe without
// a separate lock. Per DESIGN.md: "~1km bucketed + cached + throttled" —
// this is the one place all three live together.
//
// Known residual gap, not fixed: the cache check in placeName() happens
// before throttle()/the outbound call, so two concurrent calls for the
// *same* bucket can both miss the cache and both fire a lookup before
// either writes back — wasted duplicate work, not an incorrectness. Not
// currently reachable: PhotoLibraryIngestor calls this strictly
// sequentially (a plain `for` loop, no TaskGroup). Fixing it properly means
// tracking in-flight per-key requests, which isn't worth the complexity
// until something actually calls this concurrently.
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

    // Actors are reentrant at `await` points — a second `placeName()` call
    // can start running while this one is suspended inside `delaying.delay`.
    // Found in review (Codex + independent Claude subagent, same root
    // cause): the original version only stamped `lastCallAt` in a `defer`
    // that fired after the delay completed, so a reentrant call read the
    // *stale* `lastCallAt`, computed the same `remaining` wait, and both
    // calls fired their outbound lookups back-to-back — silently defeating
    // the throttle. Reserving the slot by writing `lastCallAt` synchronously
    // (no `await` between the read and the write) closes that window: a
    // reentrant call sees the already-reserved slot and queues behind it.
    private func throttle() async throws {
        let now = Date()
        let earliestNextCall = (lastCallAt ?? .distantPast).addingTimeInterval(minimumCallInterval)
        let reservedSlot = max(earliestNextCall, now)
        lastCallAt = reservedSlot
        let remaining = reservedSlot.timeIntervalSince(now)
        if remaining > 0 {
            try await delaying.delay(remaining)
        }
    }
}
