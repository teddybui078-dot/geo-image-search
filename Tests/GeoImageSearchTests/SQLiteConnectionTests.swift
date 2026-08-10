import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct SQLiteConnectionTests {
    private struct BoomError: Error {}

    @Test func executeAndQueryRoundTrip() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")
        try await connection.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("hello", at: 1) })

        let names = try await connection.query("SELECT name FROM t", map: { $0.columnText(0) })
        #expect(names == ["hello"])
    }

    @Test func nullBindingRoundTrips() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, value TEXT)")
        try await connection.run("INSERT INTO t (value) VALUES (?)", bind: { try $0.bind(String?.none, at: 1) })

        let values = try await connection.query("SELECT value FROM t", map: { $0.columnOptionalText(0) })
        #expect(values == [nil])
    }

    @Test func transactionCommitsOnSuccess() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        try await connection.transaction { conn in
            try conn.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("a", at: 1) })
            try conn.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("b", at: 1) })
        }

        let count = try await connection.query("SELECT COUNT(*) FROM t", map: { $0.columnInt64(0) })
        #expect(count == [2])
    }

    @Test func transactionRollsBackOnThrow() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        await #expect(throws: BoomError.self) {
            try await connection.transaction { conn in
                try conn.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("a", at: 1) })
                throw BoomError()
            }
        }

        let count = try await connection.query("SELECT COUNT(*) FROM t", map: { $0.columnInt64(0) })
        #expect(count == [0])
    }

    @Test func blobRoundTripsAsFloats() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, vec BLOB)")
        let vector: [Float] = [1.5, 2.5, 3.5]
        try await connection.run("INSERT INTO t (vec) VALUES (?)", bind: { try $0.bind(vector, at: 1) })

        let rows = try await connection.query("SELECT vec FROM t", map: { $0.columnBlobAsFloats(0) })
        #expect(rows == [vector])
    }

    // bind(_:Data?:) has no production caller in this diff (the one BLOB
    // column, embeddings, binds [Float] instead) but is part of the
    // SQLiteStatement wrapper's public surface and was otherwise completely
    // untested — round-trip known bytes through it via the existing
    // float-blob column reader to prove both the byte count and pointer
    // handling are correct.
    @Test func dataBlobBindRoundTripsViaFloatColumnReader() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, payload BLOB)")
        let vector: [Float] = [9.5, -3.25]
        let payload = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        try await connection.run("INSERT INTO t (payload) VALUES (?)", bind: { try $0.bind(payload, at: 1) })

        let rows = try await connection.query("SELECT payload FROM t", map: { $0.columnBlobAsFloats(0) })
        #expect(rows == [vector])
    }

    @Test func nilDataBindsAsNull() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, payload BLOB)")
        try await connection.run("INSERT INTO t (payload) VALUES (?)", bind: { try $0.bind(Data?.none, at: 1) })

        let isNull = try await connection.query("SELECT payload IS NULL FROM t", map: { $0.columnBool(0) })
        #expect(isNull == [true])
    }

    // runThrowsOnPrepareFailure below covers a *prepare*-time failure
    // (nonexistent table). SQLiteStatement.step()'s error branch — reached
    // when a statement prepares fine but sqlite3_step itself fails, e.g. a
    // runtime constraint violation — was otherwise never exercised.
    @Test func runThrowsOnStepFailureFromConstraintViolation() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT UNIQUE)")
        try await connection.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("dup", at: 1) })

        await #expect(throws: SQLiteError.self) {
            try await connection.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("dup", at: 1) })
        }
    }

    @Test func openThrowsForUnwritablePath() throws {
        #expect(throws: SQLiteError.self) {
            _ = try SQLiteConnection(path: "/nonexistent-dir-\(UUID().uuidString)/db.sqlite3")
        }
    }

    @Test func executeThrowsOnMalformedSQL() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        await #expect(throws: SQLiteError.self) {
            try await connection.execute("NOT VALID SQL")
        }
    }

    @Test func runThrowsOnPrepareFailure() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        await #expect(throws: SQLiteError.self) {
            try await connection.run("INSERT INTO nonexistent_table (x) VALUES (?)", bind: { try $0.bind("x", at: 1) })
        }
    }

    // Actor isolation should serialize concurrent writers — this stress
    // test drives real concurrent tasks at the same connection rather than
    // relying solely on reading the isolation code.
    @Test func concurrentWritesDoNotRaceOrLoseRows() async throws {
        let connection = try SQLiteConnection(path: ":memory:")
        try await connection.execute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    _ = try? await connection.run("INSERT INTO t (name) VALUES (?)", bind: { try $0.bind("row-\(i)", at: 1) })
                }
            }
        }

        let count = try await connection.query("SELECT COUNT(*) FROM t", map: { $0.columnInt64(0) })
        #expect(count == [50])
    }
}
