import SwiftUI

struct ChatView: View {
    @ObservedObject var viewModel: ChatViewModel
    @State private var apiKeyDraft = ""

    var body: some View {
        content
            .task { await viewModel.refreshAPIKeyState() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.apiKeyState {
        case .missing:
            keyEntryBanner(prompt: "Enter your OpenAI API key to start chatting.")
        case .invalid:
            keyEntryBanner(prompt: "That API key looks invalid. Enter a new one.")
        case .quotaExhausted:
            keyEntryBanner(
                prompt: "Your OpenAI account is out of quota. Check your billing, then try again.",
                showsField: false
            )
        case .valid:
            VStack(spacing: 0) {
                messageList
                Divider()
                composer
            }
        }
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.messages) { message in
                    ChatBubble(message: message)
                }
                if viewModel.isSending {
                    ProgressView()
                        .padding(.leading, 8)
                }
            }
            .padding()
        }
    }

    private var composer: some View {
        HStack {
            TextField("Ask about your photos…", text: $viewModel.draftText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await viewModel.send() } }
            Button("Send") { Task { await viewModel.send() } }
                .disabled(viewModel.draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSending)
        }
        .padding()
    }

    private func keyEntryBanner(prompt: String, showsField: Bool = true) -> some View {
        VStack(spacing: 12) {
            Text(prompt)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if showsField {
                SecureField("sk-...", text: $apiKeyDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                Button("Save") {
                    let key = apiKeyDraft
                    apiKeyDraft = ""
                    Task { await viewModel.saveAPIKey(key) }
                }
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button("Check again") { Task { await viewModel.refreshAPIKeyState() } }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ChatBubble: View {
    let message: DisplayMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .padding(10)
                .background(message.role == .user ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
