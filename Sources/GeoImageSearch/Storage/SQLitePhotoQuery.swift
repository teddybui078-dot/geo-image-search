import Foundation

struct SQLitePhotoQuery: PhotoQuery, Sendable {
    let connection: SQLiteConnection
    let embeddingDimension: Int

    // Derived from Schema.photoColumnNames (must match
    // PhotoAssetRowMapping.decode's column order) rather than hand-
    // duplicated — same source SQLitePhotoStore's INSERT column list uses.
    private static let photoColumns = Schema.photoColumnNames.joined(separator: ", ")
    private static let photoColumnsP = Schema.photoColumnNames.map { "p.\($0)" }.joined(separator: ", ")

    func allActivePhotosWithLocation() async throws -> [PhotoAsset] {
        try await connection.query(
            """
            SELECT \(Self.photoColumns) FROM photos
            WHERE deleted_at IS NULL AND latitude IS NOT NULL AND longitude IS NOT NULL
            ORDER BY captured_at
            """,
            map: PhotoAssetRowMapping.decode
        )
    }

    // Deliberately does NOT filter on GPS presence — DESIGN.md Premise 7:
    // no-GPS photos stay date/semantic-searchable, only excluded from
    // globe pins (that's allActivePhotosWithLocation's job).
    func byDateRange(start: Date, end: Date) async throws -> [PhotoAsset] {
        try await connection.query(
            """
            SELECT \(Self.photoColumns) FROM photos
            WHERE captured_at BETWEEN ? AND ? AND deleted_at IS NULL
            ORDER BY captured_at
            """,
            bind: { stmt in
                try stmt.bind(start.unixSecondsClamped, at: 1)
                try stmt.bind(end.unixSecondsClamped, at: 2)
            },
            map: PhotoAssetRowMapping.decode
        )
    }

    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset] {
        let box = GeoMath.boundingBox(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
        // Overlap predicate, not containment. SQLite's R-Tree module stores
        // coordinates as 32-bit floats and deliberately rounds min down /
        // max up (expands boxes outward) so its own index never produces
        // false negatives. A containment test (`r.min_lat >= ? AND r.max_lat
        // <= ?`) runs against that expansion backwards: verified empirically
        // that a realistic-precision GPS coordinate's stored box can fail
        // `min_lat >= queryMinLat` purely from the outward rounding, even
        // for an exact self-query. Overlap (`max >= queryMin AND min <=
        // queryMax`) is the correct predicate for an expanded stored box.
        //
        // lonRanges has two entries when the box crosses the antimeridian
        // (±180°) — a single [minLon, maxLon] range can't express that
        // wraparound, so each range contributes its own overlap clause,
        // OR'd together.
        let lonClause = box.lonRanges.map { _ in "(r.max_lon >= ? AND r.min_lon <= ?)" }.joined(separator: " OR ")
        let candidates = try await connection.query(
            """
            SELECT \(Self.photoColumnsP) FROM photos p
            JOIN photos_rtree r ON r.id = p.rowid
            WHERE r.max_lat >= ? AND r.min_lat <= ? AND (\(lonClause))
              AND p.deleted_at IS NULL
            """,
            bind: { stmt in
                var index: Int32 = 1
                try stmt.bind(box.minLat, at: index); index += 1
                try stmt.bind(box.maxLat, at: index); index += 1
                for range in box.lonRanges {
                    try stmt.bind(range.minLon, at: index); index += 1
                    try stmt.bind(range.maxLon, at: index); index += 1
                }
            },
            map: PhotoAssetRowMapping.decode
        )

        // The R-Tree only gives a box approximation — enforce the true
        // circular radius here.
        return candidates.filter { asset in
            guard let lat = asset.latitude, let lon = asset.longitude else { return false }
            return GeoMath.haversineDistanceKm(lat1: latitude, lon1: longitude, lat2: lat, lon2: lon) <= radiusKm
        }
    }

    func bySimilarity(embedding: [Float], limit: Int) async throws -> [PhotoAsset] {
        guard embedding.count == embeddingDimension else {
            throw SQLiteError.embeddingDimensionMismatch(expected: embeddingDimension, actual: embedding.count)
        }
        // SQLite treats a negative LIMIT as "unlimited" — without this guard,
        // a non-positive `limit` would silently return every active embedded
        // photo instead of erroring or returning nothing.
        guard limit > 0 else { return [] }
        // Overfetch past the caller's limit before filtering deleted_at:
        // if we asked vec0 for exactly `limit` nearest neighbors and only
        // then filtered out soft-deleted rows, a deleted photo among the
        // top-k would silently shrink the result below `limit`. 4x buffer,
        // capped at 4096 — sqlite-vec's own hard ceiling on a KNN query's k
        // value (verified empirically: it throws a catchable error above
        // that, not a crash). A prior version of this formula capped at
        // min(max(limit, 200), 4096), which collapsed to overfetchK == limit
        // (zero deletion buffer) for any limit in [200, 4095] — silently
        // contradicting this comment's own guarantee for exactly the range
        // where a real personal-library query would plausibly land. `limit
        // * 4` traps on overflow for a huge `limit` (e.g. Int.max), so the
        // multiply is guarded behind a check that avoids it once `limit`
        // alone already implies the 4096 cap applies.
        //
        // Known limitation, not fixable within this design: once `limit`
        // itself reaches 4096 — sqlite-vec's own hard k-ceiling — there is
        // no room left to overfetch at all (overfetchK == limit, zero
        // deletion buffer), and for `limit` beyond 4096 the result is
        // structurally capped at 4096 regardless of how many active matches
        // actually exist, the same way a plain SQL LIMIT larger than the
        // table's row count just returns fewer rows without erroring. Not
        // worth guarding against explicitly: a personal library's agent
        // tool calls this with limit defaulting to 20 (CONTRACT.md's
        // semantic_search draft schema) — asking for 4096+ nearest matches
        // is already far outside any real usage this app has.
        let overfetchK = limit >= 1024 ? 4096 : min(limit * 4, 4096)

        return try await connection.query(
            """
            WITH knn AS (
                SELECT asset_id, distance FROM photo_embeddings
                WHERE embedding MATCH ?
                ORDER BY distance
                LIMIT ?
            )
            SELECT \(Self.photoColumnsP) FROM knn
            JOIN photos p ON p.id = knn.asset_id
            WHERE p.deleted_at IS NULL
            ORDER BY knn.distance
            LIMIT ?
            """,
            bind: { stmt in
                try stmt.bind(embedding, at: 1)
                try stmt.bind(Int64(overfetchK), at: 2)
                try stmt.bind(Int64(limit), at: 3)
            },
            map: PhotoAssetRowMapping.decode
        )
    }

    // CONTRACT.md's signature has no proximity/distance knob, and TODOS.md
    // item 2 explicitly defers real trip-scoping (timezone handling,
    // road-trip edge cases, calibrated thresholds) to later with real data.
    // Deliberately simple v1: split on time gaps, drop short stops, done.
    func clusterTrips(minStopDuration: TimeInterval, maxTravelGap: TimeInterval) async throws -> [TripCluster] {
        let photos = try await allActivePhotosWithLocation() // active, GPS-present, sorted by captured_at

        var clusters: [[PhotoAsset]] = []
        var current: [PhotoAsset] = []
        for photo in photos {
            if let last = current.last, photo.capturedAt.timeIntervalSince(last.capturedAt) > maxTravelGap {
                clusters.append(current)
                current = []
            }
            current.append(photo)
        }
        if !current.isEmpty {
            clusters.append(current)
        }

        return clusters.compactMap { members in
            guard let first = members.first, let last = members.last else { return nil }
            guard last.capturedAt.timeIntervalSince(first.capturedAt) >= minStopDuration else { return nil }

            let latitudes = members.compactMap(\.latitude)
            let longitudes = members.compactMap(\.longitude)
            let centroidLatitude = latitudes.reduce(0, +) / Double(latitudes.count)
            // Circular mean, not arithmetic — a trip spanning the
            // antimeridian (e.g. Fiji) would otherwise average to a
            // centroid near Greenwich instead of near the dateline.
            let centroidLongitude = GeoMath.circularMeanDegrees(longitudes)

            let placeNameCounts = Dictionary(grouping: members.compactMap(\.placeName), by: { $0 }).mapValues(\.count)
            let placeName = placeNameCounts.max(by: { $0.value < $1.value })?.key

            return TripCluster(
                id: UUID().uuidString,
                assetIDs: members.map(\.id),
                startDate: first.capturedAt,
                endDate: last.capturedAt,
                centroidLatitude: centroidLatitude,
                centroidLongitude: centroidLongitude,
                placeName: placeName
            )
        }
    }

    func embeddedAssetIDs(modelVersion: String) async throws -> Set<String> {
        Set(try await connection.query(
            "SELECT asset_id FROM photo_embedding_meta WHERE model_version = ?",
            bind: { try $0.bind(modelVersion, at: 1) },
            map: { $0.columnText(0) }
        ))
    }
}
