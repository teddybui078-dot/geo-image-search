import Foundation

// CONTRACT.md — locked shape, shared across every feature worktree.
struct PhotoAsset: Identifiable, Codable, Sendable {
    let id: String              // PHAsset.localIdentifier — stable across relaunches
    let latitude: Double?       // nil if the photo has no GPS data
    let longitude: Double?
    let capturedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?        // soft delete — nil means active
    let placeName: String?      // cached reverse-geocode result, nil until geocoded
    let isLivePhoto: Bool       // true = indexed as photo, motion component ignored (v1)
}
