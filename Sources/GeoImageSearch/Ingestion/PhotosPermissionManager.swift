import Photos

// Next Step 1 — request Photos/iCloud access, list assets with PHAsset.location.
final class PhotosPermissionManager {
    func requestAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }
}
