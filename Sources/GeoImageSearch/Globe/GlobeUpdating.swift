import Foundation

// Mirrors CONTRACT.md's native -> JS bridge message shapes exactly (see
// "Globe update protocol" section), so add-3dmap's real WebViewBridge can
// conform to this later with zero call-site changes in the chat UI.
// add-3dmap hasn't landed yet — WebViewBridge (Globe/WebViewBridge.swift) is
// still an empty stub — so the chat UI codes against this protocol today,
// backed by LoggingGlobeUpdater below.
protocol GlobeUpdating: Sendable {
    func setPins(_ pins: [GlobePin]) async
    func focusRegion(_ bounds: GlobeBounds) async
    func highlightAssets(ids: [String]) async
}

struct GlobePin: Sendable, Equatable {
    let id: String
    let lat: Double
    let lon: Double
}

struct GlobeBounds: Sendable, Equatable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

// No-op/log-only implementation used until add-3dmap lands a real
// WebViewBridge conforming to GlobeUpdating.
final class LoggingGlobeUpdater: GlobeUpdating, Sendable {
    private let sink: @Sendable (String) -> Void

    init(sink: @escaping @Sendable (String) -> Void = { print($0) }) {
        self.sink = sink
    }

    func setPins(_ pins: [GlobePin]) async {
        sink("GlobeUpdating.setPins: \(pins.count) pin(s)")
    }

    func focusRegion(_ bounds: GlobeBounds) async {
        sink("GlobeUpdating.focusRegion: lat \(bounds.minLat)...\(bounds.maxLat), lon \(bounds.minLon)...\(bounds.maxLon)")
    }

    func highlightAssets(ids: [String]) async {
        sink("GlobeUpdating.highlightAssets: \(ids.count) id(s)")
    }
}

extension GlobePin {
    // GPS-present assets only — matches DESIGN.md Premise 7 (no-GPS photos
    // are excluded from globe pins, not from the tool results themselves).
    init?(asset: PhotoAsset) {
        guard let lat = asset.latitude, let lon = asset.longitude else { return nil }
        self.init(id: asset.id, lat: lat, lon: lon)
    }
}

extension GlobeBounds {
    // nil when there are no GPS-present assets to bound.
    init?(assets: [PhotoAsset]) {
        let coordinates = assets.compactMap { asset -> (Double, Double)? in
            guard let lat = asset.latitude, let lon = asset.longitude else { return nil }
            return (lat, lon)
        }
        guard let firstLat = coordinates.first?.0 else { return nil }
        var minLat = firstLat, maxLat = firstLat
        var minLon = coordinates[0].1, maxLon = coordinates[0].1
        for (lat, lon) in coordinates {
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
        }
        self.init(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon)
    }
}
