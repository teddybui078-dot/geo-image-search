import SwiftUI

@main
struct GeoImageSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var viewModel: ChatViewModel?
    @State private var bootstrapError: String?

    var body: some View {
        Group {
            if let viewModel {
                ChatView(viewModel: viewModel)
            } else if let bootstrapError {
                Text("Failed to start: \(bootstrapError)")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ProgressView("Starting Geo Image Search…")
            }
        }
        .task {
            do {
                viewModel = try await AppComposition.makeChatViewModel()
            } catch {
                bootstrapError = error.localizedDescription
            }
        }
    }
}
