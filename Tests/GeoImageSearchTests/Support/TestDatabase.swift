@testable import GeoImageSearch

// Shared in-memory database setup for tests — was duplicated verbatim as a
// private helper across 6 test files; consolidated here so a future change
// to how the fixture store/query pair is constructed only needs one edit.
enum TestDatabase {
    static func makeStoreAndQuery(embeddingDimension: Int = 4) async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        try await SQLiteDatabase.openInMemory(embeddingDimension: embeddingDimension)
    }

    static func makeStore(embeddingDimension: Int = 4) async throws -> (store: SQLitePhotoStore, connection: SQLiteConnection) {
        let (store, _) = try await SQLiteDatabase.openInMemory(embeddingDimension: embeddingDimension)
        return (store, store.connection)
    }
}
