import Foundation

// byLocation uses these together: an R-Tree bounding-box prefilter (cheap,
// index-accelerated, but only an approximation of a circle), followed by an
// exact haversine cutoff to enforce the true radiusKm circle.
enum GeoMath {
    private static let kmPerDegreeLatitude = 111.32
    private static let earthRadiusKm = 6371.0

    struct BoundingBox {
        let minLat: Double
        let maxLat: Double
        // One range normally; two when the box crosses the ±180° antimeridian
        // (e.g. a query near Fiji or the Bering Strait) — a single [minLon,
        // maxLon] range can't express "wraps from 179° through 180°/-180° to
        // -179°", so that case splits into [minLon, 180] ∪ [-180, maxLon].
        let lonRanges: [(minLon: Double, maxLon: Double)]
    }

    static func boundingBox(latitude: Double, longitude: Double, radiusKm: Double) -> BoundingBox {
        let latDelta = radiusKm / kmPerDegreeLatitude
        let minLat = latitude - latDelta
        let maxLat = latitude + latDelta

        // If the search radius reaches as far as (or past) the nearest pole,
        // every longitude can contain a point within radiusKm — the search
        // circle goes "over the top" and back down the other side, where
        // longitude is meaningless. No finite longitude window is correct
        // here regardless of how wide; verified against a concrete case: a
        // point 16.7km from a query 0.11km from the pole, at a longitude
        // 135° away, was silently excluded by the lonScale-clamped formula
        // below before this check existed (the clamp only prevents
        // infinity/NaN, it doesn't make the box geometrically correct).
        let poleDistanceKm = (90 - abs(latitude)) * kmPerDegreeLatitude
        if radiusKm >= poleDistanceKm {
            return BoundingBox(minLat: minLat, maxLat: maxLat, lonRanges: [(-180, 180)])
        }

        // Guarded away from zero so near-pole photos don't blow lonDelta up
        // to infinity/NaN — correctness for the actual near-pole case is
        // handled by the poleDistanceKm check above, not by this clamp.
        let lonScale = max(cos(latitude * .pi / 180), 0.01)
        let lonDelta = radiusKm / (kmPerDegreeLatitude * lonScale)
        let rawMinLon = longitude - lonDelta
        let rawMaxLon = longitude + lonDelta

        if rawMaxLon - rawMinLon >= 360 {
            // Radius so large (or lonScale so small near a pole) the box
            // covers every longitude — a single full-width range.
            return BoundingBox(minLat: minLat, maxLat: maxLat, lonRanges: [(-180, 180)])
        } else if rawMinLon < -180 {
            return BoundingBox(minLat: minLat, maxLat: maxLat, lonRanges: [
                (rawMinLon + 360, 180),
                (-180, rawMaxLon)
            ])
        } else if rawMaxLon > 180 {
            return BoundingBox(minLat: minLat, maxLat: maxLat, lonRanges: [
                (rawMinLon, 180),
                (-180, rawMaxLon - 360)
            ])
        } else {
            return BoundingBox(minLat: minLat, maxLat: maxLat, lonRanges: [(rawMinLon, rawMaxLon)])
        }
    }

    // A plain arithmetic mean of longitudes breaks for a set of points
    // spanning the antimeridian (e.g. +179.9° and -179.9° average to ~0°,
    // placing the mean near Greenwich instead of near the dateline where
    // the points actually are). Circular mean (via unit vectors) handles
    // this correctly for any set of angles.
    static func circularMeanDegrees(_ degrees: [Double]) -> Double {
        guard !degrees.isEmpty else { return 0 }
        let radians = degrees.map { $0 * .pi / 180 }
        let sumSin = radians.reduce(0) { $0 + sin($1) }
        let sumCos = radians.reduce(0) { $0 + cos($1) }
        return atan2(sumSin, sumCos) * 180 / .pi
    }

    // sin²(Δlon/2) is periodic in Δlon with period 360°, so this already
    // handles antimeridian-crossing pairs correctly without any explicit
    // longitude wrapping/normalization — verified: for lon1=179, lon2=-179
    // (2° apart, wrapping), the raw 358° difference and the true 2°
    // difference produce the same sin² magnitude.
    static func haversineDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
