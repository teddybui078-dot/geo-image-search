import Foundation

// Shared decoder for `photos` rows, used by every SQLitePhotoQuery method.
// Queries must SELECT these 9 columns in this exact order (see
// SQLitePhotoQuery's photoColumns/photoColumnsP constants) rather than
// relying on `SELECT *` column ordering.
enum PhotoAssetRowMapping {
    static func decode(_ statement: SQLiteStatement) -> PhotoAsset {
        PhotoAsset(
            id: statement.columnText(0),
            latitude: statement.columnOptionalDouble(1),
            longitude: statement.columnOptionalDouble(2),
            capturedAt: Date(timeIntervalSince1970: TimeInterval(statement.columnInt64(3))),
            createdAt: Date(timeIntervalSince1970: TimeInterval(statement.columnInt64(4))),
            updatedAt: Date(timeIntervalSince1970: TimeInterval(statement.columnInt64(5))),
            deletedAt: statement.columnOptionalInt64(6).map { Date(timeIntervalSince1970: TimeInterval($0)) },
            placeName: statement.columnOptionalText(7),
            isLivePhoto: statement.columnBool(8)
        )
    }
}
