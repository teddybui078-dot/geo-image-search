import CoreLocation
import Photos
import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoAssetSnapshotTests {
    @Test func mapsGPSAndTimestampsFromAsset() {
        let asset = FakePhotoLibraryAsset(localIdentifier: "abc")
        let snapshot = PhotoAssetSnapshot(asset: asset)

        #expect(snapshot.localIdentifier == "abc")
        #expect(snapshot.latitude == 37.7749)
        #expect(snapshot.longitude == -122.4194)
        #expect(snapshot.creationDate == asset.creationDate)
        #expect(snapshot.modificationDate == asset.modificationDate)
        #expect(snapshot.isLivePhoto == false)
    }

    @Test func mapsNoGPSAsset() {
        let asset = FakePhotoLibraryAsset(localIdentifier: "no-gps", location: nil)
        let snapshot = PhotoAssetSnapshot(asset: asset)

        #expect(snapshot.latitude == nil)
        #expect(snapshot.longitude == nil)
    }

    @Test func detectsLivePhotoViaMediaSubtypes() {
        let asset = FakePhotoLibraryAsset(localIdentifier: "live", mediaSubtypes: .photoLive)
        #expect(PhotoAssetSnapshot(asset: asset).isLivePhoto)
    }

    @Test func toPhotoAssetPrefersCreationDateForCapturedAt() {
        let snapshot = PhotoAssetSnapshot(
            localIdentifier: "id",
            latitude: 1, longitude: 2,
            creationDate: Date(timeIntervalSince1970: 100),
            modificationDate: Date(timeIntervalSince1970: 200),
            isLivePhoto: false
        )
        let asset = snapshot.toPhotoAsset(placeName: "Paris", now: Date(timeIntervalSince1970: 999))

        #expect(asset.capturedAt == Date(timeIntervalSince1970: 100))
        #expect(asset.updatedAt == Date(timeIntervalSince1970: 200))
        #expect(asset.createdAt == Date(timeIntervalSince1970: 999))
        #expect(asset.placeName == "Paris")
        #expect(asset.deletedAt == nil)
    }

    @Test func toPhotoAssetFallsBackWhenDatesMissing() {
        let now = Date(timeIntervalSince1970: 999)
        let snapshot = PhotoAssetSnapshot(
            localIdentifier: "id",
            latitude: nil, longitude: nil,
            creationDate: nil,
            modificationDate: nil,
            isLivePhoto: false
        )
        let asset = snapshot.toPhotoAsset(placeName: nil, now: now)

        #expect(asset.capturedAt == now)
        #expect(asset.updatedAt == now)
    }

    @Test func gpsCoverageReportsPercentAcrossMixedAssets() {
        let snapshots = [
            PhotoAssetSnapshot(asset: FakePhotoLibraryAsset(localIdentifier: "1")),
            PhotoAssetSnapshot(asset: FakePhotoLibraryAsset(localIdentifier: "2", location: nil)),
            PhotoAssetSnapshot(asset: FakePhotoLibraryAsset(localIdentifier: "3", location: nil)),
            PhotoAssetSnapshot(asset: FakePhotoLibraryAsset(localIdentifier: "4"))
        ]

        let report = GPSCoverageReport.measure(snapshots)

        #expect(report.totalAssets == 4)
        #expect(report.assetsWithGPS == 2)
        #expect(report.coveragePercent == 50)
    }

    @Test func gpsCoverageOfEmptyLibraryDoesNotDivideByZero() {
        let report = GPSCoverageReport.measure([])
        #expect(report.coveragePercent == 0)
    }
}
