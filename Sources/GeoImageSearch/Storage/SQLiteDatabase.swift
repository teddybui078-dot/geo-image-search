import Foundation

// Returns the raw connection for now; grows a convenience that also vends
// SQLitePhotoStore/SQLitePhotoQuery sharing this connection once those
// types exist (they don't yet at this point in the build-out).
enum SQLiteDatabase {
    static func open(atPath path: String, embeddingDimension: Int) async throws -> SQLiteConnection {
        let connection = try SQLiteConnection(path: path)
        try await Schema.create(in: connection, embeddingDimension: embeddingDimension)
        return connection
    }

    static func openInMemory(embeddingDimension: Int) async throws -> SQLiteConnection {
        try await open(atPath: ":memory:", embeddingDimension: embeddingDimension)
    }
}
