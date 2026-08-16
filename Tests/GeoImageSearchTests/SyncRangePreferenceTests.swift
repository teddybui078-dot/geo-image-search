import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct SyncDateRangeOptionTests {
    private let now = Date(timeIntervalSince1970: 1_755_302_400) // 2025-08-16T00:00:00Z

    @Test func allPhotosIsUnscoped() {
        #expect(SyncDateRangeOption.allPhotos.dateRange(now: now) == nil)
    }

    @Test func last30DaysEndsAtNowAndStartsThirtyDaysBefore() throws {
        let range = try #require(SyncDateRangeOption.last30Days.dateRange(now: now))
        #expect(range.upperBound == now)
        let expectedStart = Calendar.current.date(byAdding: .day, value: -30, to: now)
        #expect(range.lowerBound == expectedStart)
    }

    @Test func since2025StartsAtTheBeginningOf2025() throws {
        let range = try #require(SyncDateRangeOption.since2025.dateRange(now: now))
        #expect(range.upperBound == now)
        var components = DateComponents()
        components.year = 2025; components.month = 1; components.day = 1
        let expectedStart = Calendar(identifier: .gregorian).date(from: components)
        #expect(range.lowerBound == expectedStart)
    }

    @Test func since2023StartsAtTheBeginningOf2023() throws {
        let range = try #require(SyncDateRangeOption.since2023.dateRange(now: now))
        var components = DateComponents()
        components.year = 2023; components.month = 1; components.day = 1
        let expectedStart = Calendar(identifier: .gregorian).date(from: components)
        #expect(range.lowerBound == expectedStart)
    }
}

// .serialized: both tests share one UserDefaults suite name, so they can't
// safely interleave (parallel run order would otherwise race) — same
// pattern as AgentPreferencesTests.
@Suite("UserDefaultsSyncRangePreferenceStore", .serialized)
struct UserDefaultsSyncRangePreferenceStoreTests {
    private func makeStore() -> UserDefaultsSyncRangePreferenceStore {
        let defaults = UserDefaults(suiteName: "com.geoimagesearch.tests.syncRange")!
        defaults.removePersistentDomain(forName: "com.geoimagesearch.tests.syncRange")
        return UserDefaultsSyncRangePreferenceStore(defaults: defaults)
    }

    @Test("no range chosen yet returns nil")
    func returnsNilWhenUnset() {
        #expect(makeStore().selectedRange() == nil)
    }

    @Test("save then load round-trips the chosen range")
    func roundTripsSelectedRange() {
        let store = makeStore()
        store.setSelectedRange(.since2023)
        #expect(store.selectedRange() == .since2023)

        store.setSelectedRange(.allPhotos)
        #expect(store.selectedRange() == .allPhotos)
    }
}
