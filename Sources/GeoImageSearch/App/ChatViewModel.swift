import SwiftUI

struct DisplayMessage: Identifiable, Equatable, Sendable {
    enum Role: Sendable {
        case user, assistant
    }

    let id = UUID()
    let role: Role
    let text: String
}

// Drives ChatView: owns the visible message history, the OpenAI key UX
// state (TODOS.md deferred item 3), and the agent conversation. On each
// response it hands the resulting photos to GlobeUpdating so the globe
// updates alongside the chat.
@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [DisplayMessage] = []
    @Published private(set) var apiKeyState: APIKeyState = .missing
    @Published var draftText: String = ""
    @Published private(set) var isSending = false

    private let apiKeyManager: APIKeyManager
    private let agent: PhotoQueryAgent
    private let globeUpdater: any GlobeUpdating
    private let errorReporting: any ErrorReporting
    private var conversation: [LLMMessage] = []

    init(
        apiKeyManager: APIKeyManager,
        agent: PhotoQueryAgent,
        globeUpdater: any GlobeUpdating,
        errorReporting: any ErrorReporting
    ) {
        self.apiKeyManager = apiKeyManager
        self.agent = agent
        self.globeUpdater = globeUpdater
        self.errorReporting = errorReporting
    }

    func refreshAPIKeyState() async {
        do {
            apiKeyState = try await apiKeyManager.currentState()
        } catch {
            // A transport failure while validating isn't evidence the key
            // is bad — leave the last-known state alone and just report it.
            errorReporting.report(.llmTimeout, context: "ChatViewModel.refreshAPIKeyState")
        }
    }

    func saveAPIKey(_ key: String) async {
        do {
            apiKeyState = try await apiKeyManager.save(key)
        } catch {
            errorReporting.report(.llmTimeout, context: "ChatViewModel.saveAPIKey")
        }
    }

    func clearAPIKey() {
        try? apiKeyManager.clear()
        apiKeyState = .missing
    }

    func send() async {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }

        draftText = ""
        messages.append(DisplayMessage(role: .user, text: text))
        isSending = true
        defer { isSending = false }

        do {
            let result = try await agent.ask(text, priorMessages: conversation)
            conversation = result.updatedMessages
            messages.append(DisplayMessage(role: .assistant, text: result.responseText))
            await updateGlobe(with: result.assets)
        } catch let error as AppError {
            errorReporting.report(error, context: "ChatViewModel.send")
            if case .llmInvalidAPIKey = error {
                apiKeyState = .invalid
            }
            messages.append(DisplayMessage(role: .assistant, text: friendlyMessage(for: error)))
        } catch {
            messages.append(DisplayMessage(role: .assistant, text: "Something went wrong answering that: \(error.localizedDescription)"))
        }
    }

    private func updateGlobe(with assets: [PhotoAsset]) async {
        let pins = assets.compactMap(GlobePin.init(asset:))
        await globeUpdater.setPins(pins)
        await globeUpdater.highlightAssets(ids: assets.map(\.id))
        if let bounds = GlobeBounds(assets: assets) {
            await globeUpdater.focusRegion(bounds)
        }
    }

    private func friendlyMessage(for error: AppError) -> String {
        switch error {
        case .llmInvalidAPIKey:
            "Your OpenAI API key looks invalid. Check it below and try again."
        case .llmRateLimited:
            "OpenAI is rate-limiting requests right now. Try again in a moment."
        case .llmTimeout:
            "The request to OpenAI timed out. Try again."
        default:
            "Something went wrong answering that."
        }
    }
}
