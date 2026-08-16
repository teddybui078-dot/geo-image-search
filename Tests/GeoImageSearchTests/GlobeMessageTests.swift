import Testing
import Foundation
@testable import GeoImageSearch

@Suite struct GlobeMessageTests {
    // MARK: - Native -> JS

    @Test func setPinsEncodesCONTRACTShape() throws {
        let message = SetPinsMessage(pins: [GlobePin(id: "abc", lat: 1.5, lon: -2.5)])
        let json = try encodeToDictionary(message)

        #expect(json["type"] as? String == "setPins")
        let pins = try #require(json["pins"] as? [[String: Any]])
        #expect(pins.count == 1)
        #expect(pins[0]["id"] as? String == "abc")
        #expect(pins[0]["lat"] as? Double == 1.5)
        #expect(pins[0]["lon"] as? Double == -2.5)
    }

    @Test func focusRegionEncodesCONTRACTShape() throws {
        let message = FocusRegionMessage(bounds: GlobeBounds(minLat: 1, maxLat: 2, minLon: 3, maxLon: 4))
        let json = try encodeToDictionary(message)

        #expect(json["type"] as? String == "focusRegion")
        let bounds = try #require(json["bounds"] as? [String: Any])
        #expect(bounds["minLat"] as? Double == 1)
        #expect(bounds["maxLat"] as? Double == 2)
        #expect(bounds["minLon"] as? Double == 3)
        #expect(bounds["maxLon"] as? Double == 4)
    }

    @Test func highlightAssetsEncodesCONTRACTShape() throws {
        let message = HighlightAssetsMessage(ids: ["a", "b"])
        let json = try encodeToDictionary(message)

        #expect(json["type"] as? String == "highlightAssets")
        #expect(json["ids"] as? [String] == ["a", "b"])
    }

    // MARK: - JS -> Native

    @Test func parsesWebviewReady() throws {
        let message = try InboundGlobeMessage(body: ["type": "webviewReady"])
        #expect(message == .webviewReady)
    }

    @Test func parsesWebviewError() throws {
        let message = try InboundGlobeMessage(body: ["type": "webviewError", "message": "boom"])
        #expect(message == .webviewError(message: "boom"))
    }

    @Test func parsesPinSelected() throws {
        let message = try InboundGlobeMessage(body: ["type": "pinSelected", "id": "asset-1"])
        #expect(message == .pinSelected(id: "asset-1"))
    }

    @Test func rejectsNonDictionaryBody() {
        #expect(throws: InboundGlobeMessage.ParseError.invalidBody) {
            try InboundGlobeMessage(body: "not a dictionary")
        }
    }

    @Test func rejectsMissingType() {
        #expect(throws: InboundGlobeMessage.ParseError.missingType) {
            try InboundGlobeMessage(body: [String: Any]())
        }
    }

    @Test func rejectsUnknownType() {
        #expect(throws: InboundGlobeMessage.ParseError.unknownType("mystery")) {
            try InboundGlobeMessage(body: ["type": "mystery"])
        }
    }

    @Test func rejectsWebviewErrorMissingMessage() {
        #expect(throws: InboundGlobeMessage.ParseError.missingField("message")) {
            try InboundGlobeMessage(body: ["type": "webviewError"])
        }
    }

    @Test func rejectsPinSelectedMissingId() {
        #expect(throws: InboundGlobeMessage.ParseError.missingField("id")) {
            try InboundGlobeMessage(body: ["type": "pinSelected"])
        }
    }
}

private func encodeToDictionary(_ value: some Encodable) throws -> [String: Any] {
    let data = try JSONEncoder().encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}
