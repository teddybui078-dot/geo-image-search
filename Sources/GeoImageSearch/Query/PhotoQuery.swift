import Foundation

// Additive beyond CONTRACT.md's original four read methods — added by
// photo-icloud-extraction (see CONTRACT.md's "Changing the contract").
// Carries placeName alongside updatedAt so a re-upsert whose geocode call
// fails can fall back to what was already resolved, instead of a failure
// silently erasing previously-good data (found in review, see
// PhotoLibraryIngestor.resolvedPlaceName).
struct StoredPhotoIdentity: Sendable, Equatable {
    let updatedAt: Date
    let placeName: String?
}

// CONTRACT.md — locked read interface. Implemented by database-structure
// (SQLitePhotoQuery); called by q-and-a-ai-agent and add-3dmap.
//
// add-3dmap only needs allActivePhotosWithLocation() to build the
// initial globe view — it does not need the other four methods.
protocol PhotoQuery {
    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset]
    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset]
    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset]
    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster]
    func allActivePhotosWithLocation() async throws -> [PhotoAsset]

    // Additive beyond CONTRACT.md's original four read methods — added by
    // photo-icloud-extraction (see CONTRACT.md's "Changing the contract").
    // id -> (updatedAt, placeName) for every active (non-deleted) photo,
    // GPS or not. allActivePhotosWithLocation() can't serve this: it
    // excludes no-GPS rows, but relaunch sync needs every stored identifier
    // to correctly detect deletions of photos that never had GPS in the
    // first place.
    func allActiveIdentifiers() async throws -> [String: StoredPhotoIdentity]

    // Additive (CONTRACT.md's "Additive method" note under Read interface),
    // added by embedding-pipeline: lets a re-run of the embedding pipeline
    // skip assets already embedded at the current model version instead of
    // re-embedding the whole library every time.
    func embeddedAssetIDs(modelVersion: String) async throws -> Set<String>
}

extension PhotoQuery {
    // Default-empty: degrades to "nothing considered already embedded"
    // rather than failing to compile for any other conformer.
    func embeddedAssetIDs(modelVersion: String) async throws -> Set<String> { [] }
}
