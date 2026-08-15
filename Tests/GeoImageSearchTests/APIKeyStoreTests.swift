import Testing
import Foundation
@testable import GeoImageSearch

// In-memory fake so these tests never touch the real macOS Keychain.
final class InMemoryKeyStore: SecureKeyStoring, @unchecked Sendable {
    private var value: String?

    func read() throws -> String? { value }
    func save(_ value: String) throws { self.value = value }
    func delete() throws { value = nil }
}

struct StubValidator: APIKeyValidating {
    let result: APIKeyState
    func validate(apiKey: String) async throws -> APIKeyState { result }
}

@Suite struct APIKeyManagerTests {
    @Test func missingKeyReportsMissingWithoutValidating() async throws {
        let manager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        #expect(try await manager.currentState() == .missing)
    }

    @Test func emptyStringKeyReportsMissing() async throws {
        let store = InMemoryKeyStore()
        try store.save("")
        let manager = APIKeyManager(store: store, validator: StubValidator(result: .valid))
        #expect(try await manager.currentState() == .missing)
    }

    @Test func savedValidKeyReportsValid() async throws {
        let manager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .valid))
        let state = try await manager.save("sk-test")
        #expect(state == .valid)
        #expect(try await manager.currentState() == .valid)
    }

    @Test func savedInvalidKeyReportsInvalid() async throws {
        let manager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .invalid))
        let state = try await manager.save("sk-bad")
        #expect(state == .invalid)
    }

    @Test func quotaExhaustedStatePropagates() async throws {
        let manager = APIKeyManager(store: InMemoryKeyStore(), validator: StubValidator(result: .quotaExhausted))
        #expect(try await manager.save("sk-test") == .quotaExhausted)
    }

    @Test func clearRemovesStoredKey() async throws {
        let store = InMemoryKeyStore()
        let manager = APIKeyManager(store: store, validator: StubValidator(result: .valid))
        _ = try await manager.save("sk-test")
        try manager.clear()
        #expect(try store.read() == nil)
        #expect(try await manager.currentState() == .missing)
    }

    @Test func rotatingKeyOverwritesPrevious() async throws {
        let store = InMemoryKeyStore()
        let manager = APIKeyManager(store: store, validator: StubValidator(result: .valid))
        _ = try await manager.save("sk-old")
        _ = try await manager.save("sk-new")
        #expect(try manager.currentKey() == "sk-new")
    }
}

// KeychainKeyStore exercises real Security-framework calls against a
// throwaway service/account name so it doesn't collide with (or leave
// behind) anything under the app's real bundle id / account.
@Suite struct KeychainKeyStoreTests {
    private func makeStore() -> KeychainKeyStore {
        KeychainKeyStore(service: "com.geoimagesearch.tests", account: "test-key-\(UUID().uuidString)")
    }

    @Test func readReturnsNilWhenNothingStored() throws {
        let store = makeStore()
        #expect(try store.read() == nil)
    }

    @Test func saveThenReadRoundTrips() throws {
        let store = makeStore()
        try store.save("sk-round-trip")
        #expect(try store.read() == "sk-round-trip")
        try store.delete()
    }

    @Test func saveTwiceUpdatesRatherThanDuplicating() throws {
        let store = makeStore()
        try store.save("sk-first")
        try store.save("sk-second")
        #expect(try store.read() == "sk-second")
        try store.delete()
    }

    @Test func deleteIsIdempotent() throws {
        let store = makeStore()
        try store.delete()
        try store.delete()
        #expect(try store.read() == nil)
    }
}
