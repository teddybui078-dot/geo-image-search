import Foundation

struct SQLitePhotoQuery: PhotoQuery, Sendable {
    let connection: SQLiteConnection
    let embeddingDimension: Int

    private static let photoColumns = "id, latitude, longitude, captured_at, created_at, updated_at, deleted_at, place_name, is_live_photo"
    private static let photoColumnsP = "p.id, p.latitude, p.longitude, p.captured_at, p.created_at, p.updated_at, p.deleted_at, p.place_name, p.is_live_photo"

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
                try stmt.bind(Int64(start.timeIntervalSince1970), at: 1)
                try stmt.bind(Int64(end.timeIntervalSince1970), at: 2)
            },
            map: PhotoAssetRowMapping.decode
        )
    }

    func byLocation(latitude: Double, longitude: Double, radiusKm: Double) async throws -> [PhotoAsset] {
        let box = GeoMath.boundingBox(latitude: latitude, longitude: longitude, radiusKm: radiusKm)
        let candidates = try await connection.query(
            """
            SELECT \(Self.photoColumnsP) FROM photos p
            JOIN photos_rtree r ON r.id = p.rowid
            WHERE r.min_lat >= ? AND r.max_lat <= ? AND r.min_lon >= ? AND r.max_lon <= ?
              AND p.deleted_at IS NULL
            """,
            bind: { stmt in
                try stmt.bind(box.minLat, at: 1)
                try stmt.bind(box.maxLat, at: 2)
                try stmt.bind(box.minLon, at: 3)
                try stmt.bind(box.maxLon, at: 4)
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
        // Overfetch past the caller's limit before filtering deleted_at:
        // if we asked vec0 for exactly `limit` nearest neighbors and only
        // then filtered out soft-deleted rows, a deleted photo among the
        // top-k would silently shrink the result below `limit`.
        let overfetchK = min(limit * 4, 200)

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
            let centroidLongitude = longitudes.reduce(0, +) / Double(longitudes.count)

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
}
