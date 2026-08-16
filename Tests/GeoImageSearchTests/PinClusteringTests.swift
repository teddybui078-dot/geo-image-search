import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PinClusteringTests {
    @Test func mapsAssetsWithLocationToGlobePins() {
        let assets = [
            PhotoAssetFixtures.makeAsset(id: "a", latitude: 10, longitude: 20),
            PhotoAssetFixtures.makeAsset(id: "b", latitude: -5.5, longitude: 100.25)
        ]

        let pins = PinClustering.globePins(from: assets)

        #expect(pins == [
            GlobePin(id: "a", lat: 10, lon: 20),
            GlobePin(id: "b", lat: -5.5, lon: 100.25)
        ])
    }

    @Test func filtersOutAssetsMissingCoordinates() {
        let assets = [
            PhotoAssetFixtures.makeAsset(id: "has-location", latitude: 1, longitude: 2),
            PhotoAssetFixtures.makeAsset(id: "no-latitude", latitude: nil, longitude: 2),
            PhotoAssetFixtures.makeAsset(id: "no-longitude", latitude: 1, longitude: nil),
            PhotoAssetFixtures.makeAsset(id: "no-location", latitude: nil, longitude: nil)
        ]

        let pins = PinClustering.globePins(from: assets)

        #expect(pins == [GlobePin(id: "has-location", lat: 1, lon: 2)])
    }

    @Test func emptyInputProducesEmptyOutput() {
        #expect(PinClustering.globePins(from: []).isEmpty)
    }
}
