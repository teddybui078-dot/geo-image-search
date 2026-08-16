import SwiftUI

enum OnboardingStep: Equatable {
    case welcome
    case apiKey
    case tone
    case photosAccess
}

// Drives welcome -> apiKey -> tone -> photosAccess, skipping straight to
// photosAccess on repeat launches once initial setup is done (per
// OnboardingRequirements). Welcome/key/tone are asked once; photosAccess is
// re-checked live and can be reached again on any later launch. apiKeyManager
// is the same KeychainKeyStore/APIKeyManager ChatView uses
// (Agent/APIKeyStore.swift), so a key saved here is exactly what the chat
// agent reads — no separate onboarding-only Keychain entry.
struct OnboardingView: View {
    let progress: any OnboardingProgressStoring
    let apiKeyManager: APIKeyManager
    let preferencesStore: any AgentPreferencesStoring
    let photosAuthorizing: any PhotosAuthorizing
    let onComplete: () -> Void

    @State private var step: OnboardingStep
    @State private var photosDeniedMessage: String?

    init(
        requirements: OnboardingRequirements,
        progress: any OnboardingProgressStoring,
        apiKeyManager: APIKeyManager,
        preferencesStore: any AgentPreferencesStoring,
        photosAuthorizing: any PhotosAuthorizing,
        onComplete: @escaping () -> Void
    ) {
        self.progress = progress
        self.apiKeyManager = apiKeyManager
        self.preferencesStore = preferencesStore
        self.photosAuthorizing = photosAuthorizing
        self.onComplete = onComplete
        _step = State(initialValue: requirements.needsInitialSetup ? .welcome : .photosAccess)
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                WelcomeStepView(onNext: { step = .apiKey })
            case .apiKey:
                APIKeyStepView(apiKeyManager: apiKeyManager, onNext: { step = .tone })
            case .tone:
                AgentToneStepView(onNext: { tone in
                    preferencesStore.saveTone(tone)
                    progress.markInitialSetupComplete()
                    advanceToPhotosOrComplete()
                })
            case .photosAccess:
                PhotosAccessStepView(
                    deniedMessage: photosDeniedMessage,
                    onRequestAccess: {
                        let status = await photosAuthorizing.requestAccess()
                        await MainActor.run {
                            if status.isGranted {
                                photosDeniedMessage = nil
                                onComplete()
                            } else {
                                photosDeniedMessage = AppError.photosPermissionDenied.logDescription
                            }
                        }
                    }
                )
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private func advanceToPhotosOrComplete() {
        if photosAuthorizing.currentStatus().isGranted {
            onComplete()
        } else {
            step = .photosAccess
        }
    }
}
