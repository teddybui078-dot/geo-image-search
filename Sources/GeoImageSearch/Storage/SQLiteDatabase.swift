import Foundation

enum SQLiteDatabase {
    static func openConnection(atPath path: String, embeddingDimension: Int) async throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: path)
        try await Schema.create(in: connection, embeddingDimension: embeddingDimension)
        return connection
    }

    /// Opens one connection and returns a PhotoStore/PhotoQuery pair sharing
    /// it, so store writes and query reads never race two independent
    /// connections to the same file.
    static func open(
        atPath path: String,
        embeddingDimension: Int
    ) async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        let connection = try await openConnection(atPath: path, embeddingDimension: embeddingDimension)
        return (
            SQLitePhotoStore(connection: connection, embeddingDimension: embeddingDimension),
            SQLitePhotoQuery(connection: connection, embeddingDimension: embeddingDimension)
        )
    }

    static func openInMemory(
        embeddingDimension: Int
    ) async throws -> (store: SQLitePhotoStore, query: SQLitePhotoQuery) {
        try await open(atPath: ":memory:", embeddingDimension: embeddingDimension)
    }

    static func openInMemoryConnection(embeddingDimension: Int) async throws -> SQLiteConnection {
        try await openConnection(atPath: ":memory:", embeddingDimension: embeddingDimension)
    }
}
