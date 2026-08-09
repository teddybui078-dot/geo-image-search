import Foundation

struct SQLitePhotoStore: PhotoStore, Sendable {
    let connection: SQLiteConnection
    let embeddingDimension: Int

    func upsert(_ assets: [PhotoAsset]) async throws {
        try await connection.transaction { conn in
            for asset in assets {
                try conn.run(
                    """
                    INSERT INTO photos (id, latitude, longitude, captured_at, created_at, updated_at, deleted_at, place_name, is_live_photo)
                    VALUES (?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET
                        latitude = excluded.latitude,
                        longitude = excluded.longitude,
                        captured_at = excluded.captured_at,
                        updated_at = excluded.updated_at,
                        deleted_at = excluded.deleted_at,
                        place_name = excluded.place_name,
                        is_live_photo = excluded.is_live_photo
                    """,
                    bind: { stmt in
                        try stmt.bind(asset.id, at: 1)
                        try stmt.bind(asset.latitude, at: 2)
                        try stmt.bind(asset.longitude, at: 3)
                        try stmt.bind(Int64(asset.capturedAt.timeIntervalSince1970), at: 4)
                        try stmt.bind(Int64(asset.createdAt.timeIntervalSince1970), at: 5)
                        try stmt.bind(Int64(asset.updatedAt.timeIntervalSince1970), at: 6)
                        try stmt.bind(asset.deletedAt.map { Int64($0.timeIntervalSince1970) }, at: 7)
                        try stmt.bind(asset.placeName, at: 8)
                        try stmt.bind(asset.isLivePhoto, at: 9)
                    }
                )

                // photos.id is TEXT, not an alias for the implicit integer
                // rowid — R-Tree needs that rowid, and last_insert_rowid()
                // isn't reliable on the ON CONFLICT DO UPDATE path, so it's
                // looked up explicitly.
                let rowid = try conn.query(
                    "SELECT rowid FROM photos WHERE id = ?",
                    bind: { try $0.bind(asset.id, at: 1) },
                    map: { $0.columnInt64(0) }
                ).first

                guard let rowid else { continue } // can't happen: id was just upserted above

                if let latitude = asset.latitude, let longitude = asset.longitude {
                    // Point data represented as a zero-area box (min == max),
                    // the standard R-Tree technique for indexing points.
                    try conn.run(
                        "INSERT OR REPLACE INTO photos_rtree (id, min_lat, max_lat, min_lon, max_lon) VALUES (?,?,?,?,?)",
                        bind: { stmt in
                            try stmt.bind(rowid, at: 1)
                            try stmt.bind(latitude, at: 2)
                            try stmt.bind(latitude, at: 3)
                            try stmt.bind(longitude, at: 4)
                            try stmt.bind(longitude, at: 5)
                        }
                    )
                } else {
                    // GPS absent, or cleared by this upsert — no rtree row.
                    try conn.run("DELETE FROM photos_rtree WHERE id = ?", bind: { try $0.bind(rowid, at: 1) })
                }
            }
        }
    }

    func markDeleted(ids: [String]) async throws {
        let now = Int64(Date().timeIntervalSince1970)
        try await connection.transaction { conn in
            for id in ids {
                // Soft delete only — photos_rtree/photo_embeddings rows are
                // deliberately left in place; every PhotoQuery read filters
                // photos.deleted_at IS NULL instead of keeping every virtual
                // table in sync on delete.
                try conn.run(
                    "UPDATE photos SET deleted_at = ?, updated_at = ? WHERE id = ?",
                    bind: { stmt in
                        try stmt.bind(now, at: 1)
                        try stmt.bind(now, at: 2)
                        try stmt.bind(id, at: 3)
                    }
                )
            }
        }
    }

    func upsertEmbedding(_ record: EmbeddingRecord) async throws {
        guard record.vector.count == embeddingDimension else {
            throw SQLiteError.embeddingDimensionMismatch(expected: embeddingDimension, actual: record.vector.count)
        }
        try await connection.transaction { conn in
            // photo_embeddings (vec0) natively supports its own declared TEXT
            // PRIMARY KEY (asset_id) — no rowid indirection needed here,
            // unlike photos_rtree above. But unlike an ordinary table, vec0
            // doesn't honor "INSERT OR REPLACE" conflict resolution on that
            // primary key — it just raises a UNIQUE constraint error instead
            // of replacing (confirmed empirically). Explicit delete-then-
            // insert, same transaction, is the working pattern.
            try conn.run(
                "DELETE FROM photo_embeddings WHERE asset_id = ?",
                bind: { try $0.bind(record.assetID, at: 1) }
            )
            try conn.run(
                "INSERT INTO photo_embeddings (asset_id, embedding) VALUES (?, ?)",
                bind: { stmt in
                    try stmt.bind(record.assetID, at: 1)
                    try stmt.bind(record.vector, at: 2)
                }
            )
            try conn.run(
                "INSERT OR REPLACE INTO photo_embedding_meta (asset_id, model_version, generated_at) VALUES (?, ?, ?)",
                bind: { stmt in
                    try stmt.bind(record.assetID, at: 1)
                    try stmt.bind(record.modelVersion, at: 2)
                    try stmt.bind(Int64(record.generatedAt.timeIntervalSince1970), at: 3)
                }
            )
        }
    }
}
