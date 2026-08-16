import Foundation

// Despite the filename, this isn't where LOD/zoom clustering happens — that
// runs client-side in Resources/globe.js, recomputed from live camera
// altitude, which native has no visibility into (the locked bridge schema
// has no "zoom changed" JS -> native message). OpenGlobus itself has no
// built-in Entity/Layer clustering support either (verified against the
// library source directly), contrary to CONTRACT.md/DESIGN.md's original
// premise — see globe.js's header comment and vendor/VENDORED.md.
//
// What lives here: turning `PhotoAsset` into the wire-format `GlobePin`
// CONTRACT.md's setPins message expects. `allActivePhotosWithLocation()`
// already guarantees non-nil coordinates at the SQL layer
// (Storage/SQLitePhotoQuery.swift), but `PhotoAsset.latitude`/`longitude`
// are still `Double?` at the type level, so this filters defensively rather
// than force-unwrapping.
enum PinClustering {
    static func globePins(from assets: [PhotoAsset]) -> [GlobePin] {
        assets.compactMap { asset in
            guard let latitude = asset.latitude, let longitude = asset.longitude else {
                return nil
            }
            return GlobePin(id: asset.id, lat: latitude, lon: longitude)
        }
    }
}
