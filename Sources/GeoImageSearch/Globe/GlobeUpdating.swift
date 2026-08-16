import Foundation

// Mirrors CONTRACT.md's native -> JS bridge message shapes exactly (see
// "Globe update protocol" section) — WebViewBridge.swift now conforms this
// to the real globe (see the extension at the bottom of that file);
// LoggingGlobeUpdater below remains for tests/previews and any call site
// not yet wired to a live GlobeView.
//
// GlobePin/GlobeBounds themselves live in Globe/GlobeMessage.swift (the
// add-3dmap branch's wire-message types) rather than here — the two
// branches independently defined equivalent structs before merging;
// GlobeMessage.swift's Codable versions are a strict superset of what this
// file originally declared, so this file just uses those instead of
// duplicating them.
protocol GlobeUpdating: Sendable {
    func setPins(_ pins: [GlobePin]) async
    func focusRegion(_ bounds: GlobeBounds) async
    func highlightAssets(ids: [String]) async
}

// No-op/log-only implementation for tests/previews and any call site not
// yet wired to a live GlobeView/WebViewBridge.
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
