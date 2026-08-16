import SwiftUI

// Wired to the same KeychainKeyStore/APIKeyManager ChatView uses
// (Agent/APIKeyStore.swift) — a key entered here is exactly what the chat
// agent sees, not a separate onboarding-only Keychain entry that would go
// out of sync with it.
struct APIKeyStepView: View {
    let apiKeyManager: APIKeyManager
    let onNext: () -> Void

    @State private var apiKeyDraft = ""
    @State private var state: APIKeyState = .missing
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 16) {
            Text("OpenAI API Key")
                .font(.title2.bold())
            Text(prompt)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            SecureField("sk-...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            HStack {
                Button("Skip for now", action: onNext)
                Button(isChecking ? "Checking…" : "Save & Continue") {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isChecking || apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var prompt: String {
        switch state {
        case .invalid:
            "That key looks invalid. Enter a new one, or skip for now."
        case .quotaExhausted:
            "That key is valid but the account is out of quota — saved anyway, you can fix billing later."
        default:
            "Used by the chat agent to answer questions about your photos. Stored in the macOS Keychain, never in a config file. You can add this later if you don't have one yet."
        }
    }

    private func save() async {
        isChecking = true
        defer { isChecking = false }
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = (try? await apiKeyManager.save(key)) ?? .invalid
        state = result
        // .quotaExhausted still means the key itself is good — only a bad
        // key should keep the user on this step.
        if result != .invalid {
            onNext()
        }
    }
}
