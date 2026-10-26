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

    @Test(arguments: [
        #"[{"translations":[{"to":"en"}]}]"#,
        "<!DOCTYPE html><html><body>Please verify you are human.</body></html>",
    ])
    func rejectsBodiesThatAreNotTranslations(body: String) {
        do {
            _ = try BingTranslateResponse.translatedText(from: Data(body.utf8))
            Issue.record("A body without a translation must not decode")
        } catch TranslationError.invalidResponse {
            // Expected.
        } catch {
            Issue.record("Expected invalidResponse, received \(error)")
        }
    }

    @Test func reportsRejectedRequestStatus() {
        // Bing answers failures with HTTP 200 and this object, not a translation array.
        let expired = reportedError(#"{"statusCode":205,"errorMessage":""}"#)
        #expect(expired?.statusCode == 205)
        #expect(expired?.message.isEmpty == false)

        let rejected = reportedError(#"{"statusCode":400,"errorMessage":""}"#)
        #expect(rejected?.statusCode == 400)
        #expect(rejected?.message.isEmpty == false)
        // An expired session must read differently from a generic rejection.
        #expect(expired?.message != rejected?.message)

        let passthrough = reportedError(#"{"statusCode":400,"errorMessage":"Invalid request"}"#)
        #expect(passthrough?.statusCode == 400)
        #expect(passthrough?.message == "Invalid request")
    }

    private func reportedError(_ json: String) -> (statusCode: Int, message: String)? {
        do {
            _ = try BingTranslateResponse.translatedText(from: Data(json.utf8))
            return nil
        } catch TranslationError.apiError(let statusCode, let message) {
            return (statusCode, message)
        } catch {
            return nil
        }
    }
}
