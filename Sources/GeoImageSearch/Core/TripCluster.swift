import Foundation

// CONTRACT.md — locked shape, shared across every feature worktree.
struct TripCluster: Codable, Sendable {
    let id: String
    let assetIDs: [String]
    let startDate: Date
    let endDate: Date
    let centroidLatitude: Double
    let centroidLongitude: Double
    let placeName: String?
}
