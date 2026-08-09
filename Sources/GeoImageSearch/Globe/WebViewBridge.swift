import WebKit

// Next Step 3 — native -> JS via postMessage, JS -> native via WKScriptMessageHandler.
// Also owns the WKNavigationDelegate failure fallback (native error state on load/crash).
final class WebViewBridge: NSObject, WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // Handled once the message schema is versioned (see DESIGN.md).
    }
}
