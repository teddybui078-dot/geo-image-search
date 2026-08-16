import Foundation

// CONTRACT.md "Native <-> globe bridge" — locked JSON shapes, both
// directions. Keep this file and Globe/Resources/globe.js in exact sync;
// changing either without the other breaks the bridge silently (no compiler
// or runtime error on the JS side for an unrecognized message field).

struct GlobePin: Codable, Equatable, Sendable {
    let id: String
    let lat: Double
    let lon: Double
}

struct GlobeBounds: Codable, Equatable, Sendable {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}

// MARK: - Native -> JS

struct SetPinsMessage: Encodable, Sendable {
    let type = "setPins"
    let pins: [GlobePin]
}

struct FocusRegionMessage: Encodable, Sendable {
    let type = "focusRegion"
    let bounds: GlobeBounds
}

struct HighlightAssetsMessage: Encodable, Sendable {
    let type = "highlightAssets"
    let ids: [String]
}

// MARK: - JS -> Native

// WKScriptMessage.body arrives as `Any` (bridged from a JS object into
// NSDictionary/NSString/NSNumber/NSArray) — there's no JSON text to hand to
// JSONDecoder, so this parses the bridged Any directly rather than using
// Decodable synthesis.
enum InboundGlobeMessage: Equatable, Sendable {
    case webviewReady
    case webviewError(message: String)
    case pinSelected(id: String)

    enum ParseError: Error, Equatable {
        case invalidBody
        case missingType
        case unknownType(String)
        case missingField(String)
    }

    init(body: Any) throws {
        guard let dict = body as? [String: Any] else {
            throw ParseError.invalidBody
        }
        guard let type = dict["type"] as? String else {
            throw ParseError.missingType
        }
        switch type {
        case "webviewReady":
            self = .webviewReady
        case "webviewError":
            guard let message = dict["message"] as? String else {
                throw ParseError.missingField("message")
            }
            self = .webviewError(message: message)
        case "pinSelected":
            guard let id = dict["id"] as? String else {
                throw ParseError.missingField("id")
            }
            self = .pinSelected(id: id)
        default:
            throw ParseError.unknownType(type)
        }
    }
}
