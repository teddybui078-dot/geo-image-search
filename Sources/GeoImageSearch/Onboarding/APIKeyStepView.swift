import SwiftUI

struct APIKeyStepView: View {
    // nil means "skipped" — the caller distinguishes that from an entered key.
    let onNext: (String?) -> Void

    @State private var key = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("OpenAI API Key")
                .font(.title2.bold())
            Text("Used by the chat agent to answer questions about your photos. Stored in the macOS Keychain, never in a config file. You can add this later if you don't have one yet.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            SecureField("sk-...", text: $key)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
            HStack {
                Button("Skip for now") { onNext(nil) }
                Button("Save & Continue") {
                    onNext(key.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .buttonStyle(.borderedProminent)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
