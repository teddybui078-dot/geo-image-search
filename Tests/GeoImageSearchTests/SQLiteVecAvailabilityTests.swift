import Testing
import CSQLite3
import CSQLiteVec

// Regression guard for the vendoring decision itself: Apple's system
// libsqlite3 has sqlite3_auto_extension disabled, which breaks the usual
// sqlite-vec integration path. These tests exercise the vendored SQLite +
// vendored sqlite-vec build directly (bypassing the Swift wrapper, which
// doesn't exist yet at this point in the build-out) to prove R-Tree and
// vec0 both work against it. If someone later "simplifies" this back to
// the system SQLite, these tests fail loudly instead of silently.
@Suite struct SQLiteVecAvailabilityTests {
    private func openConnectionWithVec() throws -> OpaquePointer {
        var db: OpaquePointer?
        #expect(sqlite3_open(":memory:", &db) == SQLITE_OK)
        var errPtr: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_vec_init(db, &errPtr, nil)
        if let errPtr {
            sqlite3_free(errPtr)
        }
        #expect(rc == SQLITE_OK)
        return try #require(db)
    }

    @Test func rTreeVirtualTableCreates() throws {
        let db = try openConnectionWithVec()
        defer { sqlite3_close_v2(db) }

        let rc = sqlite3_exec(db, "CREATE VIRTUAL TABLE t USING rtree(id, minX, maxX)", nil, nil, nil)
        #expect(rc == SQLITE_OK)
    }

    @Test func vec0VirtualTableCreatesInsertsAndMatches() throws {
        let db = try openConnectionWithVec()
        defer { sqlite3_close_v2(db) }

        #expect(sqlite3_exec(db, "CREATE VIRTUAL TABLE e USING vec0(asset_id TEXT PRIMARY KEY, embedding FLOAT[4])", nil, nil, nil) == SQLITE_OK)

        var insertStmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "INSERT INTO e(asset_id, embedding) VALUES (?, ?)", -1, &insertStmt, nil) == SQLITE_OK)
        let vecA: [Float] = [1, 1, 1, 1]
        sqlite3_bind_text(insertStmt, 1, "a", -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        vecA.withUnsafeBufferPointer { buffer in
            _ = sqlite3_bind_blob(insertStmt, 2, buffer.baseAddress, Int32(buffer.count * MemoryLayout<Float>.size), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        #expect(sqlite3_step(insertStmt) == SQLITE_DONE)
        sqlite3_finalize(insertStmt)

        var queryStmt: OpaquePointer?
        #expect(sqlite3_prepare_v2(db, "SELECT asset_id, distance FROM e WHERE embedding MATCH ? ORDER BY distance LIMIT 5", -1, &queryStmt, nil) == SQLITE_OK)
        let queryVec: [Float] = [1, 1, 1, 1]
        queryVec.withUnsafeBufferPointer { buffer in
            _ = sqlite3_bind_blob(queryStmt, 1, buffer.baseAddress, Int32(buffer.count * MemoryLayout<Float>.size), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        #expect(sqlite3_step(queryStmt) == SQLITE_ROW)
        let assetID = String(cString: sqlite3_column_text(queryStmt, 0))
        let distance = sqlite3_column_double(queryStmt, 1)
        #expect(assetID == "a")
        #expect(distance == 0)
        sqlite3_finalize(queryStmt)
    }
}
