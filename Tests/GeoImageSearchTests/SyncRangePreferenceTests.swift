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

    // Gap found in coverage audit: displayName is what SyncRangePickerView
    // actually renders as button labels, but no test asserted its mapping
    // for any case — a typo or case fallthrough regression would only ever
    // surface visually, in a view this repo can't exercise via `swift test`.
    @Test func displayNameMatchesEachCase() {
        #expect(SyncDateRangeOption.last30Days.displayName == "Last 30 days")
        #expect(SyncDateRangeOption.since2025.displayName == "Since 2025")
        #expect(SyncDateRangeOption.since2023.displayName == "Since 2023")
        #expect(SyncDateRangeOption.allPhotos.displayName == "All photos")
    }
}

// .serialized: both tests share one UserDefaults suite name, so they can't
// safely interleave (parallel run order would otherwise race) — same
// pattern as AgentPreferencesTests.
@Suite("UserDefaultsSyncRangePreferenceStore", .serialized)
struct UserDefaultsSyncRangePreferenceStoreTests {
    private let suiteName = "com.geoimagesearch.tests.syncRange"

    private func clearedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore() -> UserDefaultsSyncRangePreferenceStore {
        UserDefaultsSyncRangePreferenceStore(defaults: clearedDefaults())
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

    // Gap found in coverage audit: selectedRange()'s two branches are "no
    // value stored" (tested above) and "parse the stored value" — only the
    // successfully-parseable case was tested. A stale/renamed enum case
    // left behind by an older app version must decode to nil, not crash or
    // silently pick a default.
    @Test("unrecognized stored raw value decodes to nil")
    func returnsNilForUnrecognizedStoredValue() {
        let defaults = clearedDefaults()
        defaults.set("legacyRemovedCase", forKey: UserDefaultsSyncRangePreferenceStore.storageKey)
        let store = UserDefaultsSyncRangePreferenceStore(defaults: defaults)

        #expect(store.selectedRange() == nil)
    }
}
