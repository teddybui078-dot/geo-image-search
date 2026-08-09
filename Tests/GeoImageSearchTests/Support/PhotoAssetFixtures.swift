import Foundation
@testable import GeoImageSearch

enum PhotoAssetFixtures {
    static func makeAsset(
        id: String,
        latitude: Double? = 37.7749,
        longitude: Double? = -122.4194,
        capturedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        deletedAt: Date? = nil,
        placeName: String? = nil,
        isLivePhoto: Bool = false
    ) -> PhotoAsset {
        PhotoAsset(
            id: id,
            latitude: latitude,
            longitude: longitude,
            capturedAt: capturedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt,
            placeName: placeName,
            isLivePhoto: isLivePhoto
        )
    }
}
