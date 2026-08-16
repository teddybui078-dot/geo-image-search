import Foundation

// Persisted so future Agent work (Agent/ToolSchemas.swift is still an empty
// stub — q-and-a-ai-agent hasn't merged to main yet) can read it to shape
// the system prompt. Nothing consumes this yet; onboarding only collects
// and stores the preference.
enum AgentTone: String, Codable, CaseIterable, Sendable {
    case warm
    case concise
    case playful

    var displayName: String {
        switch self {
        case .warm: return "Warm & conversational"
        case .concise: return "Concise & to the point"
        case .playful: return "Playful & enthusiastic"
        }
    }
}

protocol AgentPreferencesStoring: Sendable {
    func loadTone() -> AgentTone?
    func saveTone(_ tone: AgentTone)
}

// UserDefaults is thread-safe (Apple's documented guarantee) but predates
// Sendable, so it isn't annotated — @unchecked is the codebase's existing
// pattern for exactly this gap (see SerialFakeFetcher in IngestorTestDoubles.swift).
final class UserDefaultsAgentPreferencesStore: AgentPreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.geoimagesearch.agentTone"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadTone() -> AgentTone? {
        defaults.string(forKey: key).flatMap(AgentTone.init(rawValue:))
    }

    func saveTone(_ tone: AgentTone) {
        defaults.set(tone.rawValue, forKey: key)
    }
}
