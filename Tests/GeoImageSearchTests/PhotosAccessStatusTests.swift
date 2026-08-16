import Photos
import Testing
@testable import GeoImageSearch

@Suite struct PhotosAccessStatusTests {
    @Test func authorizedIsGrantedAndNotLimited() {
        let status = PhotosAccessStatus(authorizationStatus: .authorized)
        #expect(status.isGranted)
        #expect(status.isLimitedAccess == false)
    }

    @Test func limitedIsGrantedAndFlaggedAsLimited() {
        let status = PhotosAccessStatus(authorizationStatus: .limited)
        #expect(status.isGranted)
        #expect(status.isLimitedAccess)
    }

    @Test func deniedAndRestrictedAreNotGranted() {
        #expect(PhotosAccessStatus(authorizationStatus: .denied).isGranted == false)
        #expect(PhotosAccessStatus(authorizationStatus: .restricted).isGranted == false)
        #expect(PhotosAccessStatus(authorizationStatus: .notDetermined).isGranted == false)
    }
}
