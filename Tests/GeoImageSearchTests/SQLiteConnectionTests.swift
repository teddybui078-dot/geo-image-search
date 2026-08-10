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
