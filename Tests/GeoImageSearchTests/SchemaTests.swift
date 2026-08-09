import Testing
@testable import GeoImageSearch

@Suite struct SchemaTests {
    @Test func createsAllContractTablesPlusMetaCompanion() async throws {
        let connection = try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
        let tableNames = try await connection.query(
            "SELECT name FROM sqlite_master ORDER BY name",
            map: { $0.columnText(0) }
        )

        #expect(tableNames.contains("photos"))
        #expect(tableNames.contains("photos_rtree"))
        #expect(tableNames.contains("photo_embeddings"))
        #expect(tableNames.contains("photo_embedding_meta"))
    }

    @Test func photosTableColumnsMatchContract() async throws {
        let connection = try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
        let columnNames = try await connection.query(
            "PRAGMA table_info(photos)",
            map: { $0.columnText(1) } // PRAGMA table_info's 2nd column is the column name
        )

        #expect(columnNames == [
            "id", "latitude", "longitude", "captured_at",
            "created_at", "updated_at", "deleted_at", "place_name", "is_live_photo"
        ])
    }

    @Test func createIsIdempotent() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await Schema.create(in: connection, embeddingDimension: 4)
        try await Schema.create(in: connection, embeddingDimension: 4)
    }
}
