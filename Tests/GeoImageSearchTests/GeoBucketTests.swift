import Testing
@testable import GeoImageSearch

@Suite struct GeoBucketTests {
    @Test func nearbyCoordinatesShareABucket() {
        let a = GeoBucket.key(latitude: 48.85661, longitude: 2.35221)
        let b = GeoBucket.key(latitude: 48.85659, longitude: 2.35219)
        #expect(a == b)
    }

    @Test func distantCoordinatesDoNotShareABucket() {
        let paris = GeoBucket.key(latitude: 48.8566, longitude: 2.3522)
        let berlin = GeoBucket.key(latitude: 52.5200, longitude: 13.4050)
        #expect(paris != berlin)
    }
}
