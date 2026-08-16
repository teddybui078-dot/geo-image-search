import SwiftUI

struct PhotosAccessStepView: View {
    let deniedMessage: String?
    let onRequestAccess: @Sendable () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Allow Access to Photos")
                .font(.title2.bold())
            Text("Geo Image Search reads your photo library's location data to plot your trips on the globe. Photos never leave your Mac.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if let deniedMessage {
                Text(deniedMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                Button("Try Again") {
                    Task { await onRequestAccess() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("Allow Photos Access") {
                    Task { await onRequestAccess() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
