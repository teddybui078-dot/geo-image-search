import WebKit

// Native <-> JS via WKScriptMessageHandler/evaluateJavaScript. Message
// shapes are locked in CONTRACT.md — see GlobeMessage.swift for the
// Codable/parsing types this wraps, and Resources/globe.js for the JS side.
//
// `onError` (not a hardcoded ErrorReporting singleton) is how a JS-side
// runtime error becomes the same native fallback state as a WKNavigationDelegate
// load failure — GlobeView's Coordinator supplies one closure that both
// reports through the real ErrorReporting and flips the fallback UI, so both
// failure paths converge on one place instead of two independent ones.
final class WebViewBridge: NSObject, WKScriptMessageHandler {
    static let messageHandlerName = "geoImageSearchBridge"

    private let onReady: () -> Void
    private let onError: (AppError, String) -> Void
    private let onPinSelected: (String) -> Void

    // Set once GlobeView creates the WKWebView; sends are no-ops before that
    // (there's nothing to call evaluateJavaScript on yet).
    weak var webView: WKWebView?

    init(
        onReady: @escaping () -> Void,
        onError: @escaping (AppError, String) -> Void,
        onPinSelected: @escaping (String) -> Void
    ) {
        self.onReady = onReady
        self.onError = onError
        self.onPinSelected = onPinSelected
    }

    // Separated from `userContentController(_:didReceive:)` so it's testable
    // with a plain `Any` body — WKScriptMessage itself can't be constructed
    // outside of WebKit.
    func receive(body: Any) {
        do {
            switch try InboundGlobeMessage(body: body) {
            case .webviewReady:
                onReady()
            case .webviewError(let message):
                onError(.webviewLoadFailed, "globe.js reported: \(message)")
            case .pinSelected(let id):
                onPinSelected(id)
            }
        } catch {
            onError(.webviewLoadFailed, "WebViewBridge failed to parse a JS -> native message: \(error)")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        receive(body: message.body)
    }

    func setPins(_ pins: [GlobePin]) {
        send(SetPinsMessage(pins: pins))
    }

    func focusRegion(_ bounds: GlobeBounds) {
        send(FocusRegionMessage(bounds: bounds))
    }

    func highlightAssets(ids: [String]) {
        send(HighlightAssetsMessage(ids: ids))
    }

    private func send(_ message: some Encodable) {
        guard let webView else { return }
        guard let data = try? JSONEncoder().encode(message) else {
            onError(.webviewLoadFailed, "WebViewBridge failed to encode an outbound \(type(of: message))")
            return
        }
        let json = String(decoding: data, as: UTF8.self)
        webView.evaluateJavaScript("window.__geoImageSearchReceive(\(json))")
    }
}

// A synchronous method satisfies an `async` protocol requirement in Swift —
// setPins/focusRegion/highlightAssets above already match GlobeUpdating's
// shape exactly, so this is the real implementation the chat agent's
// GlobeUpdating dependency was always meant to end up calling (see
// CONTRACT.md's "Globe update protocol" section).
extension WebViewBridge: GlobeUpdating {}
