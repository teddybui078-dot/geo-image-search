import Foundation
import Testing
@testable import GeoImageSearch

// Guards the two silent-corruption bugs this vendored tokenizer (over a
// hand-rolled one, or Apple's own MobileCLIP demo tokenizer) exists to
// avoid — see README's "On-device embedding model" section:
//  1. missing truncation -> crash on long queries
//  2. an untruncated merge table -> rare words silently drop with no error
@Suite struct CLIPTokenizerTests {
    private func makeTokenizer() throws -> CLIPTokenizer {
        try CLIPTokenizer(folder: EmbeddingModelInfo.bundledTokenizerFolder)
    }

    @Test func knownPhraseTokenizesExactly() throws {
        let tokenizer = try makeTokenizer()
        // contextLength 7 matches this phrase's exact token count (SOT + 5
        // word tokens + EOT), so no padding/truncation kicks in here — a
        // pure encoding-correctness assertion against the real vendored
        // vocab/merges, not the pad/truncate behavior (covered below).
        let ids = tokenizer.encode("a photo of a cat", contextLength: 7)
        #expect(ids == [49406, 320, 1125, 539, 320, 2368, 49407])
    }

    @Test func startAndEndOfTextTokensMatchModelConstants() throws {
        #expect(CLIPTokenizer.sotTokenId == EmbeddingModelInfo.startOfTextTokenID)
        #expect(CLIPTokenizer.eotTokenId == EmbeddingModelInfo.endOfTextTokenID)
    }

    @Test func shortInputIsPaddedToContextLength() throws {
        let tokenizer = try makeTokenizer()
        let ids = tokenizer.encode("cat", contextLength: EmbeddingModelInfo.contextLength)
        #expect(ids.count == EmbeddingModelInfo.contextLength)
        #expect(ids.last == CLIPTokenizer.eotTokenId)
    }

    @Test func longInputIsTruncatedNotCrashed() throws {
        let tokenizer = try makeTokenizer()
        // Repetition well past 77 tokens' worth of words — this used to be
        // an out-of-bounds crash in Apple's own MobileCLIP demo tokenizer.
        let longQuery = Array(repeating: "photo", count: 200).joined(separator: " ")
        let ids = tokenizer.encode(longQuery, contextLength: EmbeddingModelInfo.contextLength)
        #expect(ids.count == EmbeddingModelInfo.contextLength)
        #expect(ids.first == CLIPTokenizer.sotTokenId)
        #expect(ids.last == CLIPTokenizer.eotTokenId)
    }

    @Test func rareWordIsPresentInOutput() throws {
        let tokenizer = try makeTokenizer()
        // With the untruncated-merges bug, rare words like this vanished
        // from the output entirely (compactMap silently dropping ids with
        // no encoder match) rather than throwing. Assert it's actually
        // represented by at least one non-SOT/EOT token, not silently gone.
        let ids = tokenizer.encode("hippopotamus", contextLength: EmbeddingModelInfo.contextLength)
        let contentTokens = ids.filter { $0 != CLIPTokenizer.sotTokenId && $0 != CLIPTokenizer.eotTokenId }
        #expect(!contentTokens.isEmpty)
    }

    @Test func vendoredMergesFileParsesInExpectedShape() throws {
        // Regression guard for the format mismatch fixed while vendoring:
        // this tokenizer.json's merges are space-joined strings ("i n"),
        // not [[String]] pair arrays — confirms the loader actually reads
        // real data, not an empty/malformed encoder table.
        let tokenizer = try makeTokenizer()
        #expect(tokenizer.encoder.count == 49408)
    }
}
