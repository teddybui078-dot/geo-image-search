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
// re-checked live and can be reached again on any later launch.
struct OnboardingView: View {
    let progress: any OnboardingProgressStoring
    let apiKeyStore: any APIKeyStoring
    let preferencesStore: any AgentPreferencesStoring
    let photosAuthorizing: any PhotosAuthorizing
    let onComplete: () -> Void

    @State private var step: OnboardingStep
    @State private var photosDeniedMessage: String?

    init(
        requirements: OnboardingRequirements,
        progress: any OnboardingProgressStoring,
        apiKeyStore: any APIKeyStoring,
        preferencesStore: any AgentPreferencesStoring,
        photosAuthorizing: any PhotosAuthorizing,
        onComplete: @escaping () -> Void
    ) {
        self.progress = progress
        self.apiKeyStore = apiKeyStore
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
                APIKeyStepView(onNext: { key in
                    if let key, !key.isEmpty {
                        try? apiKeyStore.save(key)
                    }
                    step = .tone
                })
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
                    },
                    onCheckAgain: {
                        if photosAuthorizing.currentStatus().isGranted {
                            photosDeniedMessage = nil
                            onComplete()
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
