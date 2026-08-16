import Foundation

// Model decision: CONTRACT.md's "Model choice, resolved" note / TODOS.md
// item 5. MobileCLIP-S2, CoreML export from apple/coreml-mobileclip.
enum EmbeddingModelInfo {
    static let modelVersion = "mobileclip-s2-v1"
    static let embeddingDimension = 512

    // Both towers share this output feature name and vector space.
    static let outputFeatureName = "final_emb_1"

    static let imageInputFeatureName = "image"
    static let imageSize = 256

    // CLIP BPE: vocab 49408, fixed 77-token context, reserved start/end ids.
    static let textInputFeatureName = "text"
    static let contextLength = 77
    static let startOfTextTokenID: Int32 = 49406
    static let endOfTextTokenID: Int32 = 49407
}

// The two CoreML packages MobileCLIP-S2 ships as — see ModelProvisioning.
enum EmbeddingModelAsset: CaseIterable, Sendable {
    case image
    case text

    var fileName: String {
        switch self {
        case .image: "mobileclip_s2_image.mlpackage"
        case .text: "mobileclip_s2_text.mlpackage"
        }
    }
}
