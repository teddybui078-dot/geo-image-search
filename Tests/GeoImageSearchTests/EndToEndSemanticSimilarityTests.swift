import CoreGraphics
import Foundation
import Testing
@testable import GeoImageSearch

// Opt-in only: guarded by a file-existence check against the real
// provisioned .mlpackage paths, so this cleanly skips (not fails) in CI or
// on a fresh checkout where the weights haven't been downloaded — per this
// project's constraint that the weight files are never committed. Run
// manually on a machine that's already provisioned the model (e.g. after
// EmbeddingQueue.run() has executed once, or a manual
// HuggingFaceModelProvisioner.ensureAvailable call).
//
// This is the standing test the README's "silent corruption" risk calls
// for: wrong image preprocessing or tokenizer corruption both still produce
// a finite, correctly-shaped 512-dim vector — only a real similarity
// comparison catches them, not a shape assertion.
@Suite struct EndToEndSemanticSimilarityTests {
    private static var defaultCacheDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GeoImageSearch/Models", isDirectory: true)
    }

    private static var defaultProvisioner: HuggingFaceModelProvisioner {
        HuggingFaceModelProvisioner(
            configuration: .init(cacheDirectory: defaultCacheDirectory),
            transport: URLSessionModelFileTransferring()
        )
    }

    // .enabled(if:) reports this test as skipped, not failed, when the
    // condition is false — the correct signal for "opt-in, not broken" on a
    // fresh checkout where the weights were never downloaded.
    private static var modelIsProvisionedLocally: Bool {
        let provisioner = defaultProvisioner
        return FileManager.default.fileExists(atPath: provisioner.localURL(for: .image).path)
            && FileManager.default.fileExists(atPath: provisioner.localURL(for: .text).path)
    }

    private func makeSolidColorImage(red: CGFloat, green: CGFloat, blue: CGFloat, size: Int = EmbeddingModelInfo.imageSize) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return try #require(context.makeImage())
    }

    @Test(.enabled(if: Self.modelIsProvisionedLocally, "MobileCLIP-S2 isn't provisioned locally — opt-in, run manually after provisioning"))
    func matchingTextQueryScoresHigherThanUnrelatedText() async throws {
        let provisioner = Self.defaultProvisioner
        let imageModelURL = provisioner.localURL(for: .image)
        let textModelURL = provisioner.localURL(for: .text)

        let imageEmbedder = try ImageEmbedder(modelURL: imageModelURL)
        let tokenizer = try CLIPTokenizer(folder: EmbeddingModelInfo.bundledTokenizerFolder)
        let textEmbedder = try TextEmbedder(modelURL: textModelURL, tokenizer: tokenizer)

        // Warm orange fixture ("sunset"-adjacent) vs. a cool blue fixture —
        // synthetic solid colors rather than a bundled photo, since the
        // goal is catching gross corruption (wrong preprocessing, tokenizer
        // bugs), not evaluating retrieval quality.
        let warmImage = try makeSolidColorImage(red: 0.95, green: 0.45, blue: 0.1)
        let imageVector = try await imageEmbedder.embed(cgImage: warmImage)

        let matchingText = try await textEmbedder.embed(text: "a warm orange sunset")
        let unrelatedText = try await textEmbedder.embed(text: "a cold blue night sky")

        let matchingScore = VectorMath.cosineSimilarity(imageVector, matchingText)
        let unrelatedScore = VectorMath.cosineSimilarity(imageVector, unrelatedText)
        #expect(matchingScore > unrelatedScore)
    }
}
