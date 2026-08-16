import Testing
import Photos
@testable import GeoImageSearch

private final class FakeOnboardingProgressStore: OnboardingProgressStoring, @unchecked Sendable {
    private(set) var completed: Bool
    init(completed: Bool = false) { self.completed = completed }
    func hasCompletedInitialSetup() -> Bool { completed }
    func markInitialSetupComplete() { completed = true }
}

@Suite("OnboardingRequirementsResolver")
struct OnboardingRequirementsTests {
    @Test("first launch needs both initial setup and Photos access")
    func firstLaunch() {
        let requirements = OnboardingRequirementsResolver.resolve(
            progress: FakeOnboardingProgressStore(completed: false),
            photosAuthorizing: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .notDetermined))
        )
        #expect(requirements.needsInitialSetup)
        #expect(requirements.needsPhotosAccess)
        #expect(!requirements.isComplete)
    }

    @Test("setup done but Photos revoked only re-asks for Photos access")
    func photosRevokedAfterSetup() {
        let requirements = OnboardingRequirementsResolver.resolve(
            progress: FakeOnboardingProgressStore(completed: true),
            photosAuthorizing: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .denied))
        )
        #expect(!requirements.needsInitialSetup)
        #expect(requirements.needsPhotosAccess)
        #expect(!requirements.isComplete)
    }

    @Test("setup done and Photos granted is fully complete")
    func fullyComplete() {
        let requirements = OnboardingRequirementsResolver.resolve(
            progress: FakeOnboardingProgressStore(completed: true),
            photosAuthorizing: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .authorized))
        )
        #expect(requirements.isComplete)
    }

    @Test("limited Photos access counts as granted")
    func limitedAccessCountsAsGranted() {
        let requirements = OnboardingRequirementsResolver.resolve(
            progress: FakeOnboardingProgressStore(completed: true),
            photosAuthorizing: FakePhotosAuthorizing(status: PhotosAccessStatus(authorizationStatus: .limited))
        )
        #expect(!requirements.needsPhotosAccess)
    }
}
