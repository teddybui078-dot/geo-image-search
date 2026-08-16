import Foundation

// Presets match what the user actually asked for when this feature was
// requested: "last month," "2023," "2025." Relative options (.last30Days)
// are computed from a passed-in `now` rather than Date() directly, so a
// photo aging out of the window over time just stops being touched (never
// marked deleted — PhotoLibraryIngestor skips deletions for any scoped
// sync) instead of needing special-case handling.
enum SyncDateRangeOption: String, CaseIterable, Sendable, Codable {
    case last30Days
    case since2025
    case since2023
    case allPhotos

    var displayName: String {
        switch self {
        case .last30Days: "Last 30 days"
        case .since2025: "Since 2025"
        case .since2023: "Since 2023"
        case .allPhotos: "All photos"
        }
    }

    // nil means unscoped — PhotoLibraryIngestor.run(dateRange:) treats nil
    // as "whole library," matching EmbeddingQueue's existing "nil dateRange
    // = distantPast...distantFuture" idiom.
    func dateRange(now: Date) -> ClosedRange<Date>? {
        switch self {
        case .last30Days:
            let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
            return start...now
        case .since2025:
            return Self.yearStart(2025)...now
        case .since2023:
            return Self.yearStart(2023)...now
        case .allPhotos:
            return nil
        }
    }

    private static func yearStart(_ year: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
}

protocol SyncRangePreferenceStoring: Sendable {
    // nil means the user hasn't chosen a range yet — that's what triggers
    // the picker prompt on the next sync.
    func selectedRange() -> SyncDateRangeOption?
    func setSelectedRange(_ option: SyncDateRangeOption)
}

// UserDefaults is thread-safe (Apple's documented guarantee) but predates
// Sendable — same @unchecked rationale as UserDefaultsOnboardingProgressStore.
final class UserDefaultsSyncRangePreferenceStore: SyncRangePreferenceStoring, @unchecked Sendable {
    // Internal (not private) so tests simulating a stale/renamed stored
    // value reference this constant instead of duplicating the literal —
    // a rename then forces the test to keep testing the real key.
    static let storageKey = "com.geoimagesearch.selectedSyncDateRange"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func selectedRange() -> SyncDateRangeOption? {
        guard let rawValue = defaults.string(forKey: Self.storageKey) else { return nil }
        return SyncDateRangeOption(rawValue: rawValue)
    }

    func setSelectedRange(_ option: SyncDateRangeOption) {
        defaults.set(option.rawValue, forKey: Self.storageKey)
    }
}
