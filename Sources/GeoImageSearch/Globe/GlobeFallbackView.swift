import SwiftUI

// DESIGN.md's /plan-eng-review decision: a WKNavigationDelegate load
// failure or crash swaps in this native SwiftUI state instead of leaving a
// silently blank window. Driven by GlobeView's `loadFailed` binding.
struct GlobeFallbackView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Globe failed to load")
                .font(.headline)
            Button("Retry", action: onRetry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
