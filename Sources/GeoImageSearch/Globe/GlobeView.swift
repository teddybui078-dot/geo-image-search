import SwiftUI
import WebKit

// Hosts the OpenGlobus WKWebView. macOS target (Package.swift is
// .macOS(.v14)) -> NSViewRepresentable, not UIViewRepresentable.
struct GlobeView: NSViewRepresentable {
    // `& Sendable` is a local constraint on top of CONTRACT.md's PhotoQuery
    // protocol (which doesn't declare it) — needed because handleReady()
    // below calls it from inside a Task, crossing an isolation boundary
    // under Swift 6 strict concurrency. SQLitePhotoQuery already conforms
    // (Storage/SQLitePhotoQuery.swift), so this doesn't constrain any real
    // conformer, just this call site.
    let photoQuery: any PhotoQuery & Sendable
    let errorReporter: any ErrorReporting
    var onPinSelected: (String) -> Void = { _ in }

    // Flipped by either a WKNavigationDelegate load failure or a JS-side
    // webviewError message — both funnel through Coordinator.handleError so
    // the SwiftUI parent can swap in GlobeFallbackView regardless of which
    // one fired (CONTRACT.md ties both to the same native fallback UI).
    @Binding var loadFailed: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            photoQuery: photoQuery,
            errorReporter: errorReporter,
            onPinSelected: onPinSelected,
            loadFailed: $loadFailed
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let photoQuery: any PhotoQuery & Sendable
        private let errorReporter: any ErrorReporting
        private let onPinSelected: (String) -> Void
        private let loadFailed: Binding<Bool>
        private var bridge: WebViewBridge?

        init(
            photoQuery: any PhotoQuery & Sendable,
            errorReporter: any ErrorReporting,
            onPinSelected: @escaping (String) -> Void,
            loadFailed: Binding<Bool>
        ) {
            self.photoQuery = photoQuery
            self.errorReporter = errorReporter
            self.onPinSelected = onPinSelected
            self.loadFailed = loadFailed
        }

        func makeWebView() -> WKWebView {
            let bridge = WebViewBridge(
                onReady: { [weak self] in self?.handleReady() },
                onError: { [weak self] error, context in self?.handleError(error, context: context) },
                onPinSelected: { [weak self] id in self?.onPinSelected(id) }
            )
            self.bridge = bridge

            let userContentController = WKUserContentController()
            userContentController.add(bridge, name: WebViewBridge.messageHandlerName)

            let configuration = WKWebViewConfiguration()
            configuration.userContentController = userContentController

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            bridge.webView = webView

            guard let indexURL = Bundle.module.url(
                forResource: "index",
                withExtension: "html",
                subdirectory: "Globe/Resources"
            ) else {
                handleError(.webviewLoadFailed, context: "GlobeView: bundled index.html not found")
                return webView
            }
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
            return webView
        }

        private func handleReady() {
            Task {
                do {
                    let assets = try await photoQuery.allActivePhotosWithLocation()
                    bridge?.setPins(PinClustering.globePins(from: assets))
                } catch {
                    // Not a webview failure — the globe rendered fine, it
                    // just has no pins yet. AppError has no case for "the
                    // local photo query failed" (its cases cover
                    // PhotosKit/CLGeocoder/LLM/webview, not storage reads),
                    // so this reports through the closest existing case
                    // without flipping loadFailed / hiding a working globe.
                    errorReporter.report(.webviewLoadFailed, context: "GlobeView: allActivePhotosWithLocation failed: \(error)")
                }
            }
        }

        private func handleError(_ error: AppError, context: String) {
            errorReporter.report(error, context: context)
            loadFailed.wrappedValue = true
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            handleError(.webviewLoadFailed, context: "WKNavigationDelegate.didFail: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            handleError(.webviewLoadFailed, context: "WKNavigationDelegate.didFailProvisionalNavigation: \(error.localizedDescription)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            handleError(.webviewLoadFailed, context: "WKNavigationDelegate.webViewWebContentProcessDidTerminate")
        }
    }
}
