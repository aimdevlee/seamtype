import Foundation
import Testing
@testable import ArasoCore

/// macOS's automatic capitalization (on by default, Notes among others) turns the word just typed
/// into `Hello` behind the input method's back. It can still be switched and fixed: its keys stay as
/// typed, and only a word changed in that one way counts as the word that went in.
@MainActor @Suite struct AppCapitalizedTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-capitalized-\(UUID().uuidString).json")
        session = InputSession(engine: DictionaryEngine(base: sharedEngine, storeURL: url))
        field.insertsOverMarked = true
    }

    /// As Notes takes marked text and inserts (real keys, 2026-10-29).
    func likeNotes() {
        field.marksFromCaret = true
        field.insertsFromCaret = true
        field.dropsEmptyInserts = true
    }

    func type(_ s: String) {
        for ch in s {
            let handled = ch.isASCII && ch.isLetter ? session.handle(.letter(ch), client: field)
                                                    : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    func korean(_ keys: String) -> String { session.engine.render(keys, as: .korean) }

    /// The app capitalizes the letter at `offset`, as it does for the first word of a sentence.
    func appCapitalizes(at offset: Int = 0) {
        let text = field.text as NSString
        field.text = text.replacingCharacters(in: NSRange(location: offset, length: 1),
                                              with: text.substring(with: NSRange(location: offset, length: 1)).uppercased())
    }

    @Test(arguments: [false, true]) func theWordCanBeFixedFromEarlierInTheLine(notes: Bool) {
        if notes { likeNotes() }
        type("hello ")
        appCapitalizes()
        field.cursor = 5
        #expect(session.handle(.cycle, client: field))
        #expect(session.fixing != nil)
        #expect(session.handle(.enter, client: field))
        #expect(session.fixing == nil)
        // Read from the keys as typed: a capital would be another jamo on some keys.
        #expect(field.text == "\(korean("hello")) ")
    }

    @Test func aShiftKeyReadsAsTyped() {
        type("terms ")
        appCapitalizes()
        field.cursor = 5
        session.handle(.cycle, client: field)
        session.handle(.enter, client: field)
        #expect(field.text == "\(korean("terms")) ")
        #expect(!field.text.hasPrefix(korean("T")))
    }

    @Test func theWordJustCommittedSwitchesAndComesBackCapitalized() {
        type("hello ")
        appCapitalizes()
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "\(korean("hello")) ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "Hello ")
    }

    @Test func goingBackPutsTheCapitalBack() {
        type("hello ")
        appCapitalizes()
        field.cursor = 5
        session.handle(.cycle, client: field)
        #expect(session.handle(.escape, client: field))
        #expect(field.text == "Hello ")
    }

    @Test func goingRoundInAFixKeepsTheCapital() {
        type("hello ")
        appCapitalizes()
        field.cursor = 5
        session.handle(.cycle, client: field)
        session.handle(.cycle, client: field) // round to English again
        session.handle(.enter, client: field)
        #expect(field.text == "Hello ")
    }

    @Test(arguments: [false, true]) func theStartMovesInsideAndKeepsTheCapital(notes: Bool) {
        if notes { likeNotes() }
        type("hello ")
        appCapitalizes()
        field.cursor = 5
        session.handle(.cycle, client: field)
        session.handle(.shiftRight, client: field)
        #expect(session.fixing?.lead == 1)
        session.handle(.enter, client: field)
        #expect(field.text == "H\(korean("ello")) ")
    }

    @Test func aLaterSentencesWordToo() {
        type("the. hello again ")
        appCapitalizes(at: 5)
        field.cursor = 7
        #expect(session.handle(.cycle, client: field))
        session.handle(.enter, client: field)
        #expect(field.text == "the. \(korean("hello")) again ")
    }

    @Test func aCapitalizedWordCanJoinAClause() {
        type("the. hello again ")
        appCapitalizes(at: 5)
        field.cursor = 2
        session.handle(.cycle, client: field)
        session.handle(.right, client: field)
        #expect(session.fixing?.count == 2)
    }

    @Test func aWordTheAppChangedAnyOtherWayIsLeftAlone() {
        for changed in ["HELLO ", "Help  ", "jello "] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-capitalized-\(UUID().uuidString).json")
            let session = InputSession(engine: DictionaryEngine(base: sharedEngine, storeURL: url))
            let field = FakeTextField()
            field.insertsOverMarked = true
            for ch in "hello " {
                if ch.isLetter ? !session.handle(.letter(ch), client: field) : !session.handle(.printable(ch), client: field) {
                    field.insertText(String(ch), replacing: nil)
                }
            }
            field.text = changed
            field.cursor = 5
            session.handle(.cycle, client: field)
            #expect(session.fixing == nil)
            #expect(field.text == changed)
        }
    }

    @Test func aWordTypedWithItsCapitalStaysItsOwn() {
        type("Hello ")
        field.cursor = 5
        session.handle(.cycle, client: field)
        session.handle(.enter, client: field)
        #expect(field.text == "\(korean("Hello")) ")
    }
}
