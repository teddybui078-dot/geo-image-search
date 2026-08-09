import Foundation

// See DESIGN.md Architecture Decisions ("Geospatial index") and
// CONTRACT.md ("Database schema") for why: SQLite's R-Tree module for
// lat/lon/radius range queries, sqlite-vec for embedding similarity.
enum Schema {
    // CONTRACT.md — exact DDL.
    static let photosTableSQL = """
    CREATE TABLE IF NOT EXISTS photos (
        id TEXT PRIMARY KEY,
        latitude REAL,
        longitude REAL,
        captured_at INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted_at INTEGER,
        place_name TEXT,
        is_live_photo INTEGER NOT NULL DEFAULT 0
    )
    """

    // R-Tree requires an INTEGER rowid, not photos.id (TEXT). Callers join
    // photos_rtree.id = photos.rowid — see SQLitePhotoStore's upsert, which
    // is where that join is actually maintained.
    static let photosRTreeSQL = """
    CREATE VIRTUAL TABLE IF NOT EXISTS photos_rtree USING rtree(
        id,
        min_lat, max_lat,
        min_lon, max_lon
    )
    """

    // Dimension is a parameter, not hardcoded — CONTRACT.md flags this as an
    // open dependency pending embedding-pipeline's CoreML model choice
    // (TODOS.md item 5). Unlike photos_rtree, vec0 natively supports its own
    // declared TEXT PRIMARY KEY (asset_id) — no rowid indirection needed here.
    static func photoEmbeddingsSQL(dimension: Int) -> String {
        "CREATE VIRTUAL TABLE IF NOT EXISTS photo_embeddings USING vec0(asset_id TEXT PRIMARY KEY, embedding FLOAT[\(dimension)])"
    }

    // Additive, beyond CONTRACT.md's literal 3-table schema: EmbeddingRecord
    // carries modelVersion/generatedAt, which have no column in vec0's
    // 2-column photo_embeddings table. This companion table preserves them.
    // Fully encapsulated behind PhotoStore/PhotoQuery — no other worktree
    // needs to know it exists.
    static let photoEmbeddingMetaTableSQL = """
    CREATE TABLE IF NOT EXISTS photo_embedding_meta (
        asset_id TEXT PRIMARY KEY,
        model_version TEXT NOT NULL,
        generated_at INTEGER NOT NULL
    )
    """

    // Additive/perf, not part of CONTRACT.md's literal DDL but harmless.
    static let indexCapturedAtSQL = "CREATE INDEX IF NOT EXISTS idx_photos_captured_at ON photos(captured_at)"
    static let indexDeletedAtSQL = "CREATE INDEX IF NOT EXISTS idx_photos_deleted_at ON photos(deleted_at)"

    static func create(in connection: SQLiteConnection, embeddingDimension: Int) async throws {
        precondition(embeddingDimension > 0, "embeddingDimension must be positive")
        try await connection.execute("PRAGMA journal_mode=WAL")
        try await connection.execute(photosTableSQL)
        try await connection.execute(photosRTreeSQL)
        try await connection.execute(photoEmbeddingsSQL(dimension: embeddingDimension))
        try await connection.execute(photoEmbeddingMetaTableSQL)
        try await connection.execute(indexCapturedAtSQL)
        try await connection.execute(indexDeletedAtSQL)
    }
}
