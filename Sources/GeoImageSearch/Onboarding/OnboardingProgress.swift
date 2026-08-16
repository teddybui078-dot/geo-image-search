import Foundation

// Welcome/API-key/tone are one shot, tracked together by a single flag —
// asking again on every launch would be nagging for a step the user already
// answered (or explicitly skipped). Photos access is different: it gates
// the globe itself, so it's recomputed live from PhotosAuthorizing on every
// launch rather than cached, per the user's explicit "every launch until
// granted" call.
struct OnboardingRequirements: Sendable, Equatable {
    let needsInitialSetup: Bool
    let needsPhotosAccess: Bool

    var isComplete: Bool { !needsInitialSetup && !needsPhotosAccess }
}

protocol OnboardingProgressStoring: Sendable {
    func hasCompletedInitialSetup() -> Bool
    func markInitialSetupComplete()
}

// UserDefaults is thread-safe (Apple's documented guarantee) but predates
// Sendable — same @unchecked rationale as UserDefaultsAgentPreferencesStore.
final class UserDefaultsOnboardingProgressStore: OnboardingProgressStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.geoimagesearch.hasCompletedInitialOnboarding"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func hasCompletedInitialSetup() -> Bool {
        defaults.bool(forKey: key)
    }

    func markInitialSetupComplete() {
        defaults.set(true, forKey: key)
    }
}

enum OnboardingRequirementsResolver {
    static func resolve(
        progress: any OnboardingProgressStoring,
        photosAuthorizing: any PhotosAuthorizing
    ) -> OnboardingRequirements {
        OnboardingRequirements(
            needsInitialSetup: !progress.hasCompletedInitialSetup(),
            needsPhotosAccess: !photosAuthorizing.currentStatus().isGranted
        )
    }
}
