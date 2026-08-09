import Foundation

// byLocation uses these together: an R-Tree bounding-box prefilter (cheap,
// index-accelerated, but only an approximation of a circle), followed by an
// exact haversine cutoff to enforce the true radiusKm circle.
enum GeoMath {
    private static let kmPerDegreeLatitude = 111.32
    private static let earthRadiusKm = 6371.0

    static func boundingBox(
        latitude: Double,
        longitude: Double,
        radiusKm: Double
    ) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let latDelta = radiusKm / kmPerDegreeLatitude
        // Guarded away from zero so near-pole photos don't blow lonDelta up
        // to infinity; a large-but-finite delta there is still correct
        // (near the poles, all longitudes are close together).
        let lonScale = max(cos(latitude * .pi / 180), 0.01)
        let lonDelta = radiusKm / (kmPerDegreeLatitude * lonScale)
        return (latitude - latDelta, latitude + latDelta, longitude - lonDelta, longitude + lonDelta)
    }

    static func haversineDistanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusKm * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
