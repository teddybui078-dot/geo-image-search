import Testing
@testable import GeoImageSearch

@Suite("KeychainAPIKeyStore")
struct APIKeyStoreTests {
    // Distinct test-only service so this can never collide with the real
    // app's stored key.
    private func makeStore() -> KeychainAPIKeyStore {
        KeychainAPIKeyStore(service: "com.geoimagesearch.tests.openai-api-key")
    }

    @Test("save, load, then delete round-trips through the real Keychain")
    func saveLoadDelete() throws {
        let store = makeStore()
        try? store.delete()

        #expect(store.load() == nil)

        try store.save("sk-test-123")
        #expect(store.load() == "sk-test-123")

        try store.save("sk-test-456")
        #expect(store.load() == "sk-test-456")

        try store.delete()
        #expect(store.load() == nil)
    }
}
