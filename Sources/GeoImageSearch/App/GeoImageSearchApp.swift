import SwiftUI

@main
struct GeoImageSearchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// Bootstraps local storage, then hosts the globe (or its fallback). Storage
// open failures aren't modeled by AppError — CONTRACT.md's enum covers
// PhotosKit/CLGeocoder/LLM/webview failures, not local storage bootstrap —
// so this is a plain error state rather than a forced-fit AppError case.
struct ContentView: View {
    private let errorReporter: any ErrorReporting = ErrorReporter()

    @State private var photoQuery: (any PhotoQuery & Sendable)?
    @State private var storageError: String?
    @State private var loadFailed = false
    @State private var retryToken = 0

    var body: some View {
        Group {
            if let storageError {
                Text("Couldn't open local storage: \(storageError)")
                    .padding()
            } else if let photoQuery {
                if loadFailed {
                    GlobeFallbackView(onRetry: {
                        loadFailed = false
                        retryToken += 1
                    })
                } else {
                    GlobeView(photoQuery: photoQuery, errorReporter: errorReporter, loadFailed: $loadFailed)
                        .id(retryToken)
                }
            } else {
                ProgressView("Opening your library…")
                    .padding()
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .task {
            await openStorage()
        }
    }

    private func openStorage() async {
        do {
            let directory = try AppPaths.photoDatabaseDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("photos.sqlite").path
            // embedding-pipeline hasn't picked a CoreML model/dimension yet
            // (CONTRACT.md's open dependency, TODOS.md item 5) — add-3dmap
            // only reads allActivePhotosWithLocation(), which never touches
            // photo_embeddings, so any positive placeholder is enough to
            // open storage. Swap for the real dimension once
            // embedding-pipeline lands.
            let (_, query) = try await SQLiteDatabase.open(atPath: path, embeddingDimension: placeholderEmbeddingDimension)
            photoQuery = query
        } catch {
            storageError = error.localizedDescription
        }
    }
}

private let placeholderEmbeddingDimension = 512

enum AppPaths {
    static func photoDatabaseDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("GeoImageSearch", isDirectory: true)
    }
}
