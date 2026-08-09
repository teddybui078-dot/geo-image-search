import Foundation

// Next Step 1a — PHAsset.localIdentifier as stable primary key, deleted_at/updated_at pattern.
struct AssetIdentity {
    let localIdentifier: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}
