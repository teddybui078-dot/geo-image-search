import Testing
import Foundation
@testable import GeoImageSearch

// .serialized: both tests share one UserDefaults suite name, so they can't
// safely interleave (parallel run order would otherwise race).
@Suite("UserDefaultsAgentPreferencesStore", .serialized)
struct AgentPreferencesTests {
    // A dedicated suite so this never touches the real app's UserDefaults.
    private func makeStore() -> UserDefaultsAgentPreferencesStore {
        let defaults = UserDefaults(suiteName: "com.geoimagesearch.tests.agentPreferences")!
        defaults.removePersistentDomain(forName: "com.geoimagesearch.tests.agentPreferences")
        return UserDefaultsAgentPreferencesStore(defaults: defaults)
    }

    @Test("no tone saved yet returns nil")
    func loadsNilWhenUnset() {
        #expect(makeStore().loadTone() == nil)
    }

    @Test("save then load round-trips the tone")
    func roundTripsTone() {
        let store = makeStore()
        store.saveTone(.playful)
        #expect(store.loadTone() == .playful)

        store.saveTone(.concise)
        #expect(store.loadTone() == .concise)
    }
}
