import CoreLocation
import Photos
@testable import GeoImageSearch

// Stands in for PHAsset in tests — PHAsset has no public initializer.
struct FakePhotoLibraryAsset: PhotoLibraryAsset {
    let localIdentifier: String
    var location: CLLocation? = CLLocation(latitude: 37.7749, longitude: -122.4194)
    var creationDate: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    var modificationDate: Date? = Date(timeIntervalSince1970: 1_700_000_100)
    var mediaSubtypes: PHAssetMediaSubtype = []
}
