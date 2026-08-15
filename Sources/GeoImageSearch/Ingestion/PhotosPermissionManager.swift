import Photos

// TODOS.md item 6 — macOS lets the user grant only a "Selected Photos"
// subset. v1 indexes whatever it's given and does not prompt or explain the
// gap (DESIGN.md's Constraints) — isLimitedAccess exists so a future UI can
// surface that, not because it's handled yet. Flagged as a known gap, not
// solved, in this pass.
struct PhotosAccessStatus: Sendable, Equatable {
    let authorizationStatus: PHAuthorizationStatus

    var isGranted: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    var isLimitedAccess: Bool {
        authorizationStatus == .limited
    }
}

// Seam over the real permission call — requesting authorization triggers a
// real system prompt/entitlement check, which can't run in a unit test.
// PhotoLibraryIngestor depends on this protocol; tests inject a fake.
protocol PhotosAuthorizing: Sendable {
    func requestAccess() async -> PhotosAccessStatus
}

// Next Step 1 — request Photos/iCloud access. `.readWrite` (not `.readOnly`)
// because PHPhotoLibrary.requestAuthorization(for:) only offers those two
// options, and this app never writes to the library — read access is all
// that's actually used.
final class PhotosPermissionManager: PhotosAuthorizing, Sendable {
    func requestAccess() async -> PhotosAccessStatus {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return PhotosAccessStatus(authorizationStatus: status)
    }
}
