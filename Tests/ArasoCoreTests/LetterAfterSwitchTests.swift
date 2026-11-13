import Foundation
import Testing
@testable import ArasoCore

/// so → 내, then on: so is learned as Korean the moment o comes, and soon (English to the engine)
/// isn't learned as Korean.
///
/// Keys typed on after a switch key picked a reading of the word being typed: the pick is learned as
/// they come, for the keys it was picked on, and the word they make isn't learned when it ends.
@MainActor @Suite struct LetterAfterSwitchTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-letter-switch-\(UUID().uuidString).json")
        session = InputSession(engine: DictionaryEngine(base: SplittingEngine(base: trilingual, english: trilingual.english,
                                                                              japanese: trilingual.segmenter), storeURL: url))
        session.activate(app: "com.apple.TextEdit")
    }

    func type(_ keys: String) {
        for ch in keys {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled, ch == " " { field.insertText(" ", replacing: nil) }
        }
    }

    func korean(_ keys: String) -> String { session.engine.render(keys, as: .korean) }
    var dictionary: UserDictionary { (session.engine as! DictionaryEngine).dictionary }

    /// so, which reads as English, switched to Korean: 내.
    func switchSoToKorean() throws {
        type("so")
        while session.readings.map({ $0.languages[$0.selected] }) != .korean {
            _ = session.handle(.cycle, client: field)
        }
        #expect(field.text == "내")
    }

    @Test func thePickIsLearnedAsTheNextKeyComes() throws {
        try switchSoToKorean()
        #expect(dictionary.languageEntry(for: "so") == nil)
        type("o")
        #expect(dictionary.languageEntry(for: "so")?.language == .korean)
        #expect(session.learned?.language == .korean)
        type("n")
        _ = session.handle(.enter, client: field)
        #expect(field.text == korean("soon")) // the word went on as Korean
        #expect(dictionary.languageEntry(for: "soon") == nil)
    }

    @Test func endingWithSpaceLearnsOnlyThePick() throws {
        try switchSoToKorean()
        type("on ")
        #expect(field.text == korean("soon") + " ")
        #expect(dictionary.languageEntry(for: "so")?.language == .korean)
        #expect(dictionary.languageEntry(for: "soon") == nil)
    }

    /// Nothing typed after the pick: the word is learned when it ends, as before.
    @Test func aPickEndedAtOnceIsLearnedThen() throws {
        try switchSoToKorean()
        type(" ")
        #expect(dictionary.languageEntry(for: "so")?.language == .korean)
    }

    /// Switched again after the keys typed on: that is a choice for the whole word, learned when it ends.
    @Test func aSwitchAfterTheKeysTypedOnLearnsTheWord() throws {
        try switchSoToKorean()
        type("on")
        _ = session.handle(.cycle, client: field) // soon: English, the engine's own
        _ = session.handle(.cycle, client: field) // and Korean again, for the whole word
        #expect(field.text == korean("soon"))
        type(" ")
        #expect(dictionary.languageEntry(for: "soon")?.language == .korean)
    }
}
