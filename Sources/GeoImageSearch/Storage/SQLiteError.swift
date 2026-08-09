import Foundation

enum SQLiteError: Error, CustomStringConvertible, Sendable {
    case openFailed(String)
    case extensionInitFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case embeddingDimensionMismatch(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .openFailed(let message):
            return "SQLite open failed: \(message)"
        case .extensionInitFailed(let message):
            return "sqlite-vec extension init failed: \(message)"
        case .prepareFailed(let message):
            return "SQLite statement prepare failed: \(message)"
        case .bindFailed(let message):
            return "SQLite parameter bind failed: \(message)"
        case .stepFailed(let message):
            return "SQLite statement execution failed: \(message)"
        case .embeddingDimensionMismatch(let expected, let actual):
            return "Embedding vector has \(actual) dimensions, expected \(expected)"
        }
    }
}
