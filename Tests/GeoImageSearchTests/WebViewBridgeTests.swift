import Testing
import Foundation
@testable import GeoImageSearch

// WKScriptMessage can't be constructed outside WebKit, so these tests drive
// WebViewBridge.receive(body:) directly — the same entry point
// userContentController(_:didReceive:) forwards message.body into. Sending
// (setPins/focusRegion/highlightAssets) needs a real WKWebView and isn't
// covered here; see GlobeMessageTests for the JSON shapes those produce.
// WKScriptMessageHandler's requirement is @MainActor-isolated, which makes
// WebViewBridge as a whole MainActor-isolated — this suite runs on
// MainActor to match, same as GlobeView's Coordinator does in practice.
@MainActor
@Suite struct WebViewBridgeTests {
    private final class Recorder {
        var readyCount = 0
        var errors: [(AppError, String)] = []
        var selectedIDs: [String] = []
    }

    private func makeBridge(_ recorder: Recorder) -> WebViewBridge {
        WebViewBridge(
            onReady: { recorder.readyCount += 1 },
            onError: { error, context in recorder.errors.append((error, context)) },
            onPinSelected: { id in recorder.selectedIDs.append(id) }
        )
    }

    @Test func webviewReadyCallsOnReady() {
        let recorder = Recorder()
        let bridge = makeBridge(recorder)

        bridge.receive(body: ["type": "webviewReady"])

        #expect(recorder.readyCount == 1)
        #expect(recorder.errors.isEmpty)
    }

    @Test func webviewErrorReportsWebviewLoadFailed() {
        let recorder = Recorder()
        let bridge = makeBridge(recorder)

        bridge.receive(body: ["type": "webviewError", "message": "globe blew up"])

        #expect(recorder.errors.count == 1)
        #expect(isWebviewLoadFailed(recorder.errors[0].0))
        #expect(recorder.errors[0].1.contains("globe blew up"))
    }

    @Test func pinSelectedCallsOnPinSelectedWithID() {
        let recorder = Recorder()
        let bridge = makeBridge(recorder)

        bridge.receive(body: ["type": "pinSelected", "id": "asset-42"])

        #expect(recorder.selectedIDs == ["asset-42"])
    }

    @Test func malformedBodyReportsWebviewLoadFailedInsteadOfCrashing() {
        let recorder = Recorder()
        let bridge = makeBridge(recorder)

        bridge.receive(body: "not a dictionary")

        #expect(recorder.errors.count == 1)
        #expect(isWebviewLoadFailed(recorder.errors[0].0))
        #expect(recorder.readyCount == 0)
        #expect(recorder.selectedIDs.isEmpty)
    }

    @Test func unknownTypeReportsWebviewLoadFailed() {
        let recorder = Recorder()
        let bridge = makeBridge(recorder)

        bridge.receive(body: ["type": "somethingElse"])

        #expect(recorder.errors.count == 1)
        #expect(isWebviewLoadFailed(recorder.errors[0].0))
    }
}

// AppError (Common/AppError.swift, owned by error-handling/CONTRACT.md)
// isn't Equatable, and adding a blanket conformance from this test file
// risks colliding with one error-handling adds later — a local case check
// avoids that entirely.
private func isWebviewLoadFailed(_ error: AppError) -> Bool {
    if case .webviewLoadFailed = error { return true }
    return false
}
