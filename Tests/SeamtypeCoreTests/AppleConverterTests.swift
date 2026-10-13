import Foundation
import Testing
@testable import SeamtypeCore

/// macOS's own Japanese engine. It's private API, so where it can't be loaded the tests have nothing
/// to check (the app then uses AzooKey).
@MainActor @Suite struct AppleConverterTests {
    let learning = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-apple-\(UUID().uuidString).json")

    @Test func variantKanjiAndEnglishSpellings() throws {
        guard let converter = AppleJapaneseConverter(learning: learning) else { return }
        #expect(converter.candidates(for: "たか").contains { $0.text == "髙" })
        #expect(converter.candidates(for: "たかはし").prefix(3).contains { $0.text == "髙橋" })
        #expect(converter.candidates(for: "とぅいっち").prefix(3).contains { $0.text == "Twitch" })
    }

    /// A completion follows the first candidate, which stays a conversion of what was typed.
    @Test func completionsAfterTheFirstCandidate() throws {
        guard let converter = AppleJapaneseConverter(learning: learning) else { return }
        let candidates = converter.candidates(for: "ゆーちゅ")
        #expect(candidates.first?.isPrediction == false)
        #expect(candidates.prefix(4).contains { $0.text == "YouTube" && $0.isPrediction })
        #expect(converter.candidates(for: "かんじ").prefix(3).contains { $0.text == "漢字" })
    }

    @Test func englishInsideAPhraseStaysAsTyped() throws {
        #expect(AppleJapaneseConverter.keepingEnglish(of: "きょうはgoogleで", in: "今日はGoogleで") == "今日はgoogleで")
        #expect(AppleJapaneseConverter.keepingEnglish(of: "ゆーちゅ", in: "YouTube") == "YouTube")
        guard let converter = AppleJapaneseConverter(learning: learning) else { return }
        #expect(converter.candidates(for: "きょうはgoogleでけんさく").first?.text == "今日はgoogleで検索")
    }

    @Test func choicesComeFirstNextTime() throws {
        guard let converter = AppleJapaneseConverter(learning: learning) else { return }
        converter.learn(ConversionCandidate(text: "監事", kanaCount: 3), for: "かんじ")
        #expect(converter.candidates(for: "かんじ").first?.text == "監事")
        converter.save()
        let later = try #require(AppleJapaneseConverter(learning: learning))
        #expect(later.candidates(for: "かんじ").first?.text == "監事")
        // A first clause is learned for its own reading.
        later.learn(ConversionCandidate(text: "京は", kanaCount: 4), for: "きょうはいいてんき")
        #expect(later.candidates(for: "きょうは").first?.text == "京は")
    }
}
