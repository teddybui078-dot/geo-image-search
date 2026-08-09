import Foundation

// CONTRACT.md — locked read interface. Implemented by database-structure
// (SQLitePhotoQuery); called by q-and-a-ai-agent and 3d-interactive-map.
//
// 3d-interactive-map only needs allActivePhotosWithLocation() to build the
// initial globe view — it does not need the other four methods.
protocol PhotoQuery {
    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset]
    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset]
    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset]
    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster]
    func allActivePhotosWithLocation() async throws -> [PhotoAsset]
}
