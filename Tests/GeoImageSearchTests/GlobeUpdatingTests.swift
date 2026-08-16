import Testing
import Foundation
@testable import GeoImageSearch

private final class CapturingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    func record(_ message: String) {
        lock.withLock { messages.append(message) }
    }

    var captured: [String] {
        lock.withLock { messages }
    }
}

@Suite struct GlobeUpdatingTests {
    @Test func loggingGlobeUpdaterRecordsSetPins() async {
        let sink = CapturingSink()
        let updater = LoggingGlobeUpdater(sink: sink.record)

        await updater.setPins([GlobePin(id: "a", lat: 1, lon: 2)])

        #expect(sink.captured.contains { $0.contains("setPins") && $0.contains("1 pin") })
    }

    @Test func loggingGlobeUpdaterRecordsFocusRegion() async {
        let sink = CapturingSink()
        let updater = LoggingGlobeUpdater(sink: sink.record)

        await updater.focusRegion(GlobeBounds(minLat: 0, maxLat: 1, minLon: 0, maxLon: 1))

        #expect(sink.captured.contains { $0.contains("focusRegion") })
    }

    @Test func loggingGlobeUpdaterRecordsHighlightAssets() async {
        let sink = CapturingSink()
        let updater = LoggingGlobeUpdater(sink: sink.record)

        await updater.highlightAssets(ids: ["a", "b"])

        #expect(sink.captured.contains { $0.contains("highlightAssets") && $0.contains("2 id") })
    }

    @Test func globePinFromAssetSkipsMissingGPS() {
        let withGPS = PhotoAssetFixtures.makeAsset(id: "has-gps", latitude: 1, longitude: 2)
        let withoutGPS = PhotoAssetFixtures.makeAsset(id: "no-gps", latitude: nil, longitude: nil)

        #expect(GlobePin(asset: withGPS) == GlobePin(id: "has-gps", lat: 1, lon: 2))
        #expect(GlobePin(asset: withoutGPS) == nil)
    }

    @Test func globeBoundsFromAssetsComputesEnclosingBox() {
        let assets = [
            PhotoAssetFixtures.makeAsset(id: "a", latitude: 0, longitude: 0),
            PhotoAssetFixtures.makeAsset(id: "b", latitude: 10, longitude: -5),
            PhotoAssetFixtures.makeAsset(id: "c", latitude: nil, longitude: nil)
        ]

        let bounds = GlobeBounds(assets: assets)

        #expect(bounds == GlobeBounds(minLat: 0, maxLat: 10, minLon: -5, maxLon: 0))
    }

    @Test func globeBoundsFromAssetsWithNoGPSIsNil() {
        let assets = [PhotoAssetFixtures.makeAsset(id: "a", latitude: nil, longitude: nil)]

        #expect(GlobeBounds(assets: assets) == nil)
    }
}
