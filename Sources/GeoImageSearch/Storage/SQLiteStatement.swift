import CSQLite3
import Foundation

// Wraps a single prepared statement. Not Sendable, not an actor — safe only
// because every instance is created and fully consumed inside one
// SQLiteConnection-isolated call and never escapes that call.
final class SQLiteStatement {
    private let stmt: OpaquePointer
    private let db: OpaquePointer

    // SQLITE_TRANSIENT — sqlite3.h defines it as a macro, which the Clang
    // importer doesn't expose to Swift, so it's reconstructed here.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(db: OpaquePointer, sql: String) throws {
        self.db = db
        var preparedStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &preparedStatement, nil) == SQLITE_OK,
              let preparedStatement else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        self.stmt = preparedStatement
    }

    deinit {
        sqlite3_finalize(stmt)
    }

    private func checkBind(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func bind(_ value: String?, at index: Int32) throws {
        if let value {
            try checkBind(sqlite3_bind_text(stmt, index, value, -1, Self.transient))
        } else {
            try checkBind(sqlite3_bind_null(stmt, index))
        }
    }

    func bind(_ value: Double?, at index: Int32) throws {
        if let value {
            try checkBind(sqlite3_bind_double(stmt, index, value))
        } else {
            try checkBind(sqlite3_bind_null(stmt, index))
        }
    }

    func bind(_ value: Int64?, at index: Int32) throws {
        if let value {
            try checkBind(sqlite3_bind_int64(stmt, index, value))
        } else {
            try checkBind(sqlite3_bind_null(stmt, index))
        }
    }

    func bind(_ value: Bool, at index: Int32) throws {
        try bind(Int64(value ? 1 : 0), at: index)
    }

    func bind(_ value: Data?, at index: Int32) throws {
        if let value {
            let result = value.withUnsafeBytes { buffer in
                sqlite3_bind_blob(stmt, index, buffer.baseAddress, Int32(buffer.count), Self.transient)
            }
            try checkBind(result)
        } else {
            try checkBind(sqlite3_bind_null(stmt, index))
        }
    }

    // Raw native-endian float32 BLOB — the format sqlite-vec expects for a
    // FLOAT[N] vec0 column (no JSON stringification).
    func bind(_ value: [Float], at index: Int32) throws {
        let result = value.withUnsafeBufferPointer { buffer in
            sqlite3_bind_blob(stmt, index, buffer.baseAddress, Int32(buffer.count * MemoryLayout<Float>.size), Self.transient)
        }
        try checkBind(result)
    }

    @discardableResult
    func step() throws -> Bool {
        switch sqlite3_step(stmt) {
        case SQLITE_ROW:
            return true
        case SQLITE_DONE:
            return false
        default:
            throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func columnIsNull(_ index: Int32) -> Bool {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
    }

    func columnText(_ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: UnsafeRawPointer(cString).assumingMemoryBound(to: CChar.self))
    }

    func columnOptionalText(_ index: Int32) -> String? {
        columnIsNull(index) ? nil : columnText(index)
    }

    func columnDouble(_ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    func columnOptionalDouble(_ index: Int32) -> Double? {
        columnIsNull(index) ? nil : columnDouble(index)
    }

    func columnInt64(_ index: Int32) -> Int64 {
        sqlite3_column_int64(stmt, index)
    }

    func columnOptionalInt64(_ index: Int32) -> Int64? {
        columnIsNull(index) ? nil : columnInt64(index)
    }

    func columnBool(_ index: Int32) -> Bool {
        columnInt64(index) != 0
    }

    func columnBlobAsFloats(_ index: Int32) -> [Float] {
        guard let pointer = sqlite3_column_blob(stmt, index) else { return [] }
        let byteCount = Int(sqlite3_column_bytes(stmt, index))
        let floatCount = byteCount / MemoryLayout<Float>.size
        let typed = pointer.assumingMemoryBound(to: Float.self)
        return Array(UnsafeBufferPointer(start: typed, count: floatCount))
    }
}
