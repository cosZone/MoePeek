import Foundation
import Testing
@testable import MoePeek

@Suite struct BingTranslateResponseTests {
    @Test func decodesEnglishToChinese() throws {
        let data = Data(#"[{"translations":[{"text":"你好","to":"zh-Hans","transliteration":{"text":"Nǐ hǎo","script":"Latn"}}],"usedLLM":true,"detectedLanguage":{"language":"en"}}]"#.utf8)
        #expect(try BingTranslateResponse.translatedText(from: data) == "你好")
    }

    @Test func decodesChineseToEnglishWithInputTransliteration() throws {
        // Shape captured from Bing for 你好 → English. The second entry is metadata.
        let data = Data(#"[{"translations":[{"text":"Hello","to":"en"}],"usedLLM":true,"detectedLanguage":{"language":"zh-Hans"}},{"inputTransliteration":"Nǐ hǎo","script":"Latn"}]"#.utf8)
        #expect(try BingTranslateResponse.translatedText(from: data) == "Hello")
    }

    @Test func acceptsAdditionalMetadataEntries() throws {
        let data = Data(#"[{"translations":[{"text":"Hello","to":"en"}]},{"inputTransliteration":"Nǐ hǎo"},{"futureMetadata":true}]"#.utf8)
        #expect(try BingTranslateResponse.translatedText(from: data) == "Hello")
    }

    @Test(arguments: ["[]", #"[{"translations":[]}]"#, #"[{"translations":[{"text":"","to":"en"}]}]"#, #"[{"inputTransliteration":"Nǐ hǎo"}]"#])
    func rejectsMissingTranslation(json: String) {
        do {
            _ = try BingTranslateResponse.translatedText(from: Data(json.utf8))
            Issue.record("A response without translation text must fail")
        } catch TranslationError.emptyResult {
            // The metadata should decode, but it cannot substitute for a translation.
        } catch {
            Issue.record("Expected emptyResult, received \(error)")
        }
    }

    @Test func rejectsMalformedTranslation() {
        #expect(throws: DecodingError.self) {
            try BingTranslateResponse.translatedText(from: Data(#"[{"translations":[{"to":"en"}]}]"#.utf8))
        }
    }
}
