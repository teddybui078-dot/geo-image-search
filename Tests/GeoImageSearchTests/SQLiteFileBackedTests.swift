import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct SQLiteFileBackedTests {
    @Test func dataAndSchemaPersistAcrossReopen() async throws {
        let tempPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("geo-image-search-test-\(UUID().uuidString).sqlite3")
            .path
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: tempPath + suffix)
            }
        }

        do {
            let connection = try await SQLiteDatabase.openConnection(atPath: tempPath, embeddingDimension: 4)
            try await connection.run(
                """
                INSERT INTO photos (id, latitude, longitude, captured_at, created_at, updated_at, is_live_photo)
                VALUES (?,?,?,?,?,?,?)
                """,
                bind: { stmt in
                    try stmt.bind("asset-1", at: 1)
                    try stmt.bind(37.7749, at: 2)
                    try stmt.bind(-122.4194, at: 3)
                    try stmt.bind(Int64(1_700_000_000), at: 4)
                    try stmt.bind(Int64(1_700_000_000), at: 5)
                    try stmt.bind(Int64(1_700_000_000), at: 6)
                    try stmt.bind(false, at: 7)
                }
            )
            // `connection` drops out of scope here, closing the file.
        }

        let reopened = try await SQLiteDatabase.openConnection(atPath: tempPath, embeddingDimension: 4)
        let ids = try await reopened.query("SELECT id FROM photos", map: { $0.columnText(0) })
        #expect(ids == ["asset-1"])
    }
}
