import Foundation
import Testing
@testable import SeamtypeCore

/// What counts as a correction and what gets learned: real engines, Japanese on.
@MainActor @Suite struct CorrectionTests {
    let field = FakeTextField()
    let session: InputSession
    let learning: LearningEngine

    init() throws {
        let dir = FileManager.default.temporaryDirectory
        learning = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter),
                                  storeURL: dir.appendingPathComponent("seamtype-corr-\(UUID().uuidString).json"))
        let converter = try #require(AzooKeyConverter(memory: dir.appendingPathComponent("seamtype-corr-\(UUID().uuidString)")))
        session = InputSession(engine: learning, policies: .escSwitches, converter: converter, japaneseEnabled: true)
        session.activate(app: "com.apple.TextEdit")
    }

    /// Letters and printable keys as themselves, "⏎" Return, "⎋" Esc, "←" left arrow.
    func type(_ script: String) {
        for ch in script {
            switch ch {
            case "⏎": if !session.handle(.enter, client: field) { field.insertText("\n", replacing: nil) }
            case "⎋": _ = session.handle(.escape, client: field)
            case "←": _ = session.handle(.left, client: field)
            case let c where c.isLetter: _ = session.handle(.letter(c), client: field)
            default: if !session.handle(.printable(ch), client: field) { field.insertText(String(ch), replacing: nil) }
            }
        }
    }

    /// The engine is unsure about "so" (English, 0.55): an Esc to 내 must still count.
    @Test func escWhileTypingIsLearnedTheSecondTime() {
        type("so⎋ ")
        #expect(field.text == "내 ")
        type("x so⎋ ")
        #expect(learning.learned["so"] == .korean)
        type("x so ")
        #expect(field.text.hasSuffix("내 "))
    }

    /// Esc after a commit passing through other readings records only where it ended up.
    @Test func undoDetourIsOneCorrection() {
        // ozzy: English → Korean (ㅐㅋ쿄) → Japanese.
        type("ozzy ⎋⎋")
        type("x ")   // any key ends the undo window
        #expect(learning.pending["ozzy"] == .japanese)
        type("ozzy ⎋⎋")
        type("x ")
        #expect(learning.learned["ozzy"] == .japanese)
    }

    /// Back to kana, then Esc to English: no apostrophe the user never typed.
    @Test func noApostropheAfterBackToKana() {
        type("henkan ⎋⎋ ")
        #expect(field.text == "henkan ")
    }

    /// Committing a clause and going back to kana for the rest isn't a correction.
    @Test func backToKanaOnTheRestIsNotACorrection() {
        type("kyouhaiitenkidesune ")
        type("←←←←←←←←⏎") // 今日は, the rest keeps converting
        type("⎋⏎")
        #expect(field.text.hasPrefix("今日は"))
        #expect(learning.pending.isEmpty)
        #expect(learning.learned.isEmpty)
    }

    /// Contractions and hyphenated words stay English with Japanese on.
    @Test(arguments: ["don't ", "aren't ", "haven't ", "won't ", "weren't ", "to-do ", "e-mail ", "can't "])
    func apostrophesAndHyphensStayEnglish(_ word: String) {
        type(word)
        #expect(field.text == word, "\(field.text)")
    }

    /// Converting a word learned as Japanese again doesn't erase it.
    @Test func learnedWordSurvivesBeingUsed() {
        learning.learn("ozzy", as: .japanese, engineChoice: .english)
        learning.learn("ozzy", as: .japanese, engineChoice: .english)
        #expect(learning.learned["ozzy"] == .japanese)
        type("ozzy ⎋ ") // convert, back to kana, convert again
        type("⏎")
        #expect(learning.learned["ozzy"] == .japanese)
    }
}
