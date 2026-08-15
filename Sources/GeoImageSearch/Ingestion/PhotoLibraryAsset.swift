import CoreLocation
import Photos

// PHAsset has no public initializer, so tests can't construct real ones, and
// PHAsset isn't Sendable, so it can never cross an async/actor boundary under
// Swift 6 strict concurrency anyway. Every pure mapping/coverage function in
// this module is written against this protocol instead — PHAsset conforms
// for the real app, a fixture struct stands in for tests — and is read
// synchronously, right at the fetch boundary, into a Sendable snapshot
// (PhotoAssetSnapshot) before anything async touches it.
protocol PhotoLibraryAsset {
    var localIdentifier: String { get }
    var location: CLLocation? { get }
    var creationDate: Date? { get }
    var modificationDate: Date? { get }
    var mediaSubtypes: PHAssetMediaSubtype { get }
}

extension PHAsset: PhotoLibraryAsset {}
