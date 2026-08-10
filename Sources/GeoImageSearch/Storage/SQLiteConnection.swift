import CSQLite3
import CSQLiteVec
import Foundation

// Single serialized connection — no pool. This is a single-user, local,
// personal-scale (~50k photo) desktop app; a connection pool would be
// solving a problem this app doesn't have.
actor SQLiteConnection {
    // OpaquePointer isn't Sendable, so `deinit` (which is nonisolated and
    // can't hop onto the actor's executor) can't touch an actor-isolated
    // stored property of this type without an explicit opt-out. Safe here:
    // deinit only runs once every other reference to this actor is gone,
    // so there's no concurrent access to race against.
    nonisolated(unsafe) private let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let openResult = sqlite3_open_v2(path, &handle, flags, nil)
        guard openResult == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error opening \(path)"
            if let handle { sqlite3_close_v2(handle) }
            throw SQLiteError.openFailed(message)
        }
        self.db = handle
        sqlite3_busy_timeout(handle, 5000)
        sqlite3_extended_result_codes(handle, 1)

        // sqlite3_vec_init is safe to call directly (no pApi/auto-extension
        // dance needed) because both CSQLite3 and CSQLiteVec are compiled
        // SQLITE_CORE-mode into this same binary. See Sources/CSQLiteVec/VENDORED.md.
        var errorPointer: UnsafeMutablePointer<CChar>?
        let initResult = sqlite3_vec_init(handle, &errorPointer, nil)
        if initResult != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            // Don't close here: self.db is already assigned above, so once
            // this initializer throws, deinit runs and closes it — an
            // explicit close here would be a double-close/use-after-free
            // (verified: Swift runs deinit on a throwing init once all
            // stored properties are set).
            throw SQLiteError.extensionInitFailed(message)
        }
    }

    deinit {
        sqlite3_close_v2(db)
    }

    /// Raw DDL/PRAGMA execution, no bound parameters, no results.
    func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorPointer)
        if result != SQLITE_OK {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorPointer)
            throw SQLiteError.stepFailed(message)
        }
    }

    /// Prepare + bind + step-to-completion, for INSERT/UPDATE/DELETE.
    @discardableResult
    func run(_ sql: String, bind: (SQLiteStatement) throws -> Void = { _ in }) throws -> Int64 {
        let statement = try SQLiteStatement(db: db, sql: sql)
        try bind(statement)
        _ = try statement.step()
        return sqlite3_last_insert_rowid(db)
    }

    /// Prepare + bind + step-while-row, mapping each row, for SELECT.
    func query<T>(
        _ sql: String,
        bind: (SQLiteStatement) throws -> Void = { _ in },
        map: (SQLiteStatement) throws -> T
    ) throws -> [T] {
        let statement = try SQLiteStatement(db: db, sql: sql)
        try bind(statement)
        var results: [T] = []
        while try statement.step() {
            results.append(try map(statement))
        }
        return results
    }

    /// Runs `body` atomically with respect to every other call into this
    /// actor. The `isolated` parameter is load-bearing: it lets `body` call
    /// `conn.run(...)`/`conn.query(...)` synchronously with no suspension
    /// point in between, which is what makes BEGIN...COMMIT atomic against
    /// interleaving from concurrent PhotoStore/PhotoQuery callers.
    func transaction<T>(_ body: @Sendable (isolated SQLiteConnection) throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body(self)
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
}
