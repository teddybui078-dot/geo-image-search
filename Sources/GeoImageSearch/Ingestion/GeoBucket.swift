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
        func rounded(_ value: Double) -> Double {
            (value * 100).rounded() / 100
        }
        return "\(rounded(latitude)),\(rounded(longitude))"
    }
}
