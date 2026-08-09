import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct PhotoStoreUpsertTests {
    private func makeStore() async throws -> (store: SQLitePhotoStore, connection: SQLiteConnection) {
        let (store, _) = try await SQLiteDatabase.openInMemory(embeddingDimension: 4)
        return (store, store.connection)
    }

    private func rtreeRowCount(for connection: SQLiteConnection, assetID: String) async throws -> Int {
        try await connection.query(
            "SELECT COUNT(*) FROM photos_rtree r JOIN photos p ON p.rowid = r.id WHERE p.id = ?",
            bind: { try $0.bind(assetID, at: 1) },
            map: { Int($0.columnInt64(0)) }
        ).first ?? 0
    }

    @Test func newAssetWithGPSGetsRTreeRow() async throws {
        let (store, connection) = try await makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: 10, longitude: 20)])

        #expect(try await rtreeRowCount(for: connection, assetID: "a") == 1)
        let box = try await connection.query(
            "SELECT r.min_lat, r.max_lat, r.min_lon, r.max_lon FROM photos_rtree r JOIN photos p ON p.rowid = r.id WHERE p.id = ?",
            bind: { try $0.bind("a", at: 1) },
            map: { ($0.columnDouble(0), $0.columnDouble(1), $0.columnDouble(2), $0.columnDouble(3)) }
        ).first
        #expect(box?.0 == 10)
        #expect(box?.1 == 10)
        #expect(box?.2 == 20)
        #expect(box?.3 == 20)
    }

    @Test func newAssetWithoutGPSGetsNoRTreeRow() async throws {
        let (store, connection) = try await makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: nil, longitude: nil)])

        #expect(try await rtreeRowCount(for: connection, assetID: "a") == 0)
    }

    @Test func reupsertingSameIDUpdatesPhotoAndReplacesRTreeRow() async throws {
        let (store, connection) = try await makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: 10, longitude: 20)])
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: 30, longitude: 40)])

        let photoCount = try await connection.query("SELECT COUNT(*) FROM photos", map: { $0.columnInt64(0) }).first
        #expect(photoCount == 1)
        #expect(try await rtreeRowCount(for: connection, assetID: "a") == 1)

        let box = try await connection.query(
            "SELECT r.min_lat, r.min_lon FROM photos_rtree r JOIN photos p ON p.rowid = r.id WHERE p.id = ?",
            bind: { try $0.bind("a", at: 1) },
            map: { ($0.columnDouble(0), $0.columnDouble(1)) }
        ).first
        #expect(box?.0 == 30)
        #expect(box?.1 == 40)
    }

    @Test func clearingGPSOnLaterUpsertRemovesRTreeRow() async throws {
        let (store, connection) = try await makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: 10, longitude: 20)])
        #expect(try await rtreeRowCount(for: connection, assetID: "a") == 1)

        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: nil, longitude: nil)])
        #expect(try await rtreeRowCount(for: connection, assetID: "a") == 0)
    }

    @Test func markDeletedSetsDeletedAtButKeepsRTreeRow() async throws {
        let (store, connection) = try await makeStore()
        try await store.upsert([PhotoAssetFixtures.makeAsset(id: "a", latitude: 10, longitude: 20)])

        try await store.markDeleted(ids: ["a"])

        let deletedAt = try await connection.query(
            "SELECT deleted_at FROM photos WHERE id = ?",
            bind: { try $0.bind("a", at: 1) },
            map: { $0.columnOptionalInt64(0) }
        ).first ?? nil
        #expect(deletedAt != nil)
        #expect(try await rtreeRowCount(for: connection, assetID: "a") == 1)
    }
}
