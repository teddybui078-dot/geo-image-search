import Foundation

// DESIGN.md: reverse geocoding is bucketed by lat/lon rounded to ~1km so
// photos taken near each other share one cached CLGeocoder lookup.
// 0.01° of latitude is ~1.11km (111km/degree) everywhere; longitude's
// physical width shrinks with cos(latitude), but bucketing on raw degrees
// rather than a precise geodesic cell is what "~1km bucketed" already means
// here — good enough to collapse most of a personal library's call volume,
// not a precision guarantee (refine only if the eval's correctness set
// shows nearby-town misattribution, per DESIGN.md).
enum GeoBucket {
    static func key(latitude: Double, longitude: Double) -> String {
        // Found in review (Claude subagent): rounding a small negative value
        // (e.g. -0.001) can produce -0.0, which is numerically equal to 0.0
        // but stringifies differently ("-0.0" vs "0.0") — silently splitting
        // one cache bucket into two for coordinates within ~1km of the
        // equator or prime meridian on opposite sides of zero. `+ 0` folds
        // -0.0 back to 0.0 without affecting any other value.
        func rounded(_ value: Double) -> Double {
            let result = (value * 100).rounded() / 100
            return result == 0 ? 0 + result : result
        }
        return "\(rounded(latitude)),\(rounded(longitude))"
    }
}
