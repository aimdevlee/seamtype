import Foundation
import Testing
@testable import ArasoCore

/// What counts as a correction and what gets learned: real engines, Japanese on.
@MainActor @Suite struct CorrectionTests {
    let field = FakeTextField()
    let session: InputSession
    let learning: DictionaryEngine

    init() throws {
        let dir = FileManager.default.temporaryDirectory
        learning = DictionaryEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter),
                                  storeURL: dir.appendingPathComponent("araso-corr-\(UUID().uuidString).json"))
        let converter = try #require(AzooKeyConverter(memory: dir.appendingPathComponent("araso-corr-\(UUID().uuidString)")))
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

    /// A word learned as mixed (gitlabdp → gitlab에) renders through the base engine: through
    /// the learning engine itself it came back as learned again, without end (a stack overflow
    /// while typing, 2026-10-15).
    @Test func learnedMixedWordRendersWithoutRecursing() {
        learning.learn("gitlabdp", as: .mixed, engineChoice: .english)
        learning.learn("gitlabdp", as: .mixed, engineChoice: .english)
        #expect(learning.learned["gitlabdp"] == .mixed)
        let d = learning.decide("gitlabdp", context: DecisionContext())
        #expect(d.language == .mixed)
        #expect(d.output == "gitlab에")
        type("gitlabdp ")
        #expect(field.text == "gitlab에 ")
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

    /// One correction is weak: it turns a close call ("so" with nothing before it) but isn't
    /// learned, and typing the word as corrected keeps it.
    @Test func oneCorrectionTurnsACloseCall() {
        type("so⎋ ")
        session.activate(app: "com.apple.TextEdit")
        type("so ")
        #expect(field.text == "내 내 ")
        #expect(learning.pending == ["so": .korean] && learning.learned.isEmpty)
        // Switched back where the nudge turned it: forgotten, not a weak entry the other way.
        type("⎋⎋x ")   // 내 → そ → so
        #expect(field.text.hasSuffix("내 so x "))
        #expect(learning.pending.isEmpty && learning.learned.isEmpty)
    }

    /// A word learned as English splits off a particle typed after it: ghostty에, not ghost쇼에.
    @Test func learnedWordWithParticle() {
        type("ghosttydp ")
        #expect(field.text == "ghost쇼에 ")
        learning.learn("ghostty", as: .english, engineChoice: .korean)
        learning.learn("ghostty", as: .english, engineChoice: .korean)
        type("ghosttydp ")
        #expect(field.text == "ghost쇼에 ghostty에 ")
    }

    /// A word added for one app is typed so there only.
    @Test func wordAddedForAnApp() {
        learning.add(.init(keys: "rt", language: .english, source: .user, apps: ["com.apple.TextEdit"]))
        type("rt ")
        session.activate(app: "com.apple.Notes")
        type("rt ")
        #expect(field.text == "rt ㄱㅅ ")
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

    /// Back to kana (henkan'), switched to English, then more keys: the pick is learned for henkan,
    /// without the n marker the switch took away, not for the word the keys make.
    @Test func keysAfterASwitchFromKanaLearnThePickWithoutTheMarker() {
        type("henkan ⎋⎋")
        #expect(field.text == "henkan")
        type("s")
        #expect(learning.pending["henkan"] == .english)
        type(" ")
        #expect(learning.pending["henkans"] == nil)
        #expect(learning.pending["henkan'"] == nil)
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
