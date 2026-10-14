import Foundation
import Testing
@testable import SeamtypeCore

extension AppPolicies {
    /// Esc switches languages, as the tests of Esc cycling need (the default leaves Esc to the app).
    static let escSwitches = AppPolicies(overrides: [defaultKey: .init(switchKeys: [.escape, .shiftEscape])])
}

/// A text field: committed text, an optional marked (underlined) span, and a caret.
final class FakeTextField: TextClient {
    var text = ""
    var marked = NSRange(location: NSNotFound, length: 0)
    var cursor = 0
    /// Simulates apps that don't support reading back their text.
    var readable = true

    func setMarkedText(_ s: String) {
        let ns = text as NSString
        let target = marked.location != NSNotFound ? marked : NSRange(location: cursor, length: 0)
        text = ns.replacingCharacters(in: target, with: s)
        let length = (s as NSString).length
        marked = length > 0 ? NSRange(location: target.location, length: length) : NSRange(location: NSNotFound, length: 0)
        cursor = target.location + length
    }

    func setMarkedText(_ s: String, replacing range: NSRange) {
        let ns = text as NSString
        let target = marked.location != NSNotFound ? NSUnionRange(range, marked) : range
        text = ns.replacingCharacters(in: target, with: s)
        let length = (s as NSString).length
        marked = length > 0 ? NSRange(location: target.location, length: length) : NSRange(location: NSNotFound, length: 0)
        cursor = target.location + length
    }

    func insertText(_ s: String, replacing range: NSRange?) {
        let target = range ?? (marked.location != NSNotFound ? marked : NSRange(location: cursor, length: 0))
        text = (text as NSString).replacingCharacters(in: target, with: s)
        marked = NSRange(location: NSNotFound, length: 0)
        cursor = target.location + (s as NSString).length
    }

    func selectedRange() -> NSRange { NSRange(location: cursor, length: 0) }
    func markedRange() -> NSRange { marked }
    func text(in range: NSRange) -> String? {
        guard readable, NSMaxRange(range) <= (text as NSString).length else { return nil }
        return (text as NSString).substring(with: range)
    }
}

@MainActor @Suite struct InputSessionTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-session-\(UUID().uuidString).json")
        session = InputSession(engine: LearningEngine(base: sharedEngine, storeURL: url), policies: .escSwitches)
    }

    @discardableResult
    func type(_ s: String) -> [Bool] {
        // Keys the input method passes on are typed by the app, as in a real text field.
        s.map { ch in
            let handled = ch.isASCII && ch.isLetter ? session.handle(.letter(ch), client: field)
                                                    : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
            return handled
        }
    }

    @Test func typesMixedSentence() {
        type("dkssudgktpdy hello ")
        #expect(field.text == "안녕하세요 hello ")
    }

    @Test func escAfterCommitFlipsTheWordAndLearnsIt() {
        type("hello ")
        #expect(field.text == "hello ")
        #expect(session.handle(.escape, client: field))
        #expect(field.text == "ㅗ디ㅣㅐ ")
        #expect(field.cursor == ("ㅗ디ㅣㅐ " as NSString).length)
        // Esc again flips back.
        #expect(session.handle(.escape, client: field))
        #expect(field.text == "hello ")
        // Flipping back to the engine's own choice clears the learned override.
        type("hello ")
        #expect(field.text == "hello hello ")
    }

    /// One Esc changes only that word (a habitual Esc shouldn't stick); the same
    /// correction a second time is remembered.
    @Test func flippedChoiceIsRememberedTheSecondTime() {
        type("rjtm ")
        let first = field.text
        session.handle(.escape, client: field)
        let flipped = field.text
        #expect(flipped != first)
        type("rjtm ")
        #expect(field.text == flipped + first)
        session.handle(.escape, client: field)
        #expect(field.text == flipped + flipped)
        type("rjtm ")
        #expect(field.text == flipped + flipped + flipped)
    }

    @Test func flipOnlyAppliesToTheWordBeforeTheCaret() {
        type("dkssud ")
        field.cursor = 0 // user clicked elsewhere
        #expect(!session.handle(.escape, client: field))
        #expect(field.text == "안녕 ")
    }

    @Test func escPassesThroughWhenTextCannotBeVerified() {
        field.readable = false
        type("dkssud ")
        #expect(!session.handle(.escape, client: field))
        #expect(field.text == "안녕 ")
    }

    @Test func anyOtherKeyEndsTheFlipWindow() {
        type("dkssud ")
        #expect(!session.handle(.other, client: field))
        #expect(!session.handle(.escape, client: field))
        #expect(field.text == "안녕 ")
    }

    /// The app's own Delete: the character before the caret.
    func appDelete() {
        if !session.handle(.delete, client: field) {
            field.insertText("", replacing: NSRange(location: field.cursor - 1, length: 1))
        }
    }

    /// Space before looking, then Delete and Esc: the word still changes.
    @Test func deleteAfterCommitKeepsTheWordChangeable() {
        type("dkssud ")
        appDelete()
        #expect(field.text == "안녕")
        #expect(session.handle(.escape, client: field))
        #expect(field.text == "dkssud" && field.cursor == 6)
        type(" ")
        #expect(field.text == "dkssud ")
    }

    @Test func deleteAfterPunctuationKeepsTheWordChangeable() {
        type("hello.")
        appDelete()
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "ㅗ디ㅣㅐ")
    }

    /// Only the boundary: a second Delete takes a letter of the word and ends the chance.
    @Test func secondDeleteEndsTheFlipWindow() {
        type("dkssud ")
        appDelete()
        appDelete()
        #expect(field.text == "안")
        #expect(!session.handle(.escape, client: field))
        #expect(field.text == "안")
    }

    /// ⇧Esc is Seamtype's key: when there is nothing to change it is dropped, not sent to the
    /// app as an Esc (Claude Code clears its draft on Esc).
    @Test func shiftEscWithNothingToChangeNeverReachesTheApp() {
        #expect(session.handle(.cycle, client: field))
        field.readable = false
        type("dkssud ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "안녕 ")
        #expect(!session.handle(.escape, client: field)) // plain Esc still goes on
    }

    @Test func escWhileComposingFlipsThePreview() {
        type("dkssud")
        #expect(field.text == "안녕")
        session.handle(.escape, client: field)
        #expect(field.text == "dkssud")
        type(" ")
        #expect(field.text == "dkssud ")
    }

    @Test func deleteRemovesKeystrokes() {
        type("dkssud")
        session.handle(.delete, client: field)
        #expect(field.text == "안녀")
    }

    /// As the system's 2-set input: the syllable being typed goes jamo by jamo, earlier ones whole.
    @Test func deleteKoreanLikeTheSystem() {
        type("gksrnr")
        #expect(field.text == "한국")
        for expected in ["한구", "한ㄱ", "한", ""] {
            session.handle(.delete, client: field)
            #expect(field.text == expected)
        }
        type("dkssudgktpdy")
        for expected in ["안녕하세ㅇ", "안녕하세", "안녕하", "안녕"] {
            session.handle(.delete, client: field)
            #expect(field.text == expected)
        }
        type("gk")
        #expect(field.text == "안녕하")
        session.handle(.delete, client: field)
        #expect(field.text == "안녕ㅎ")
    }

    /// After a Delete the syllable being typed stays apart from the ones before, as in the system
    /// input: 세요 → 세ㅇ → 세유 (not 셍, 셍ㅠ).
    @Test func retypingAfterDeleteKeepsSyllablesApart() {
        type("dkssudgktpdy")
        session.handle(.delete, client: field)
        type("b ")
        #expect(field.text == "안녕하세유 ")
    }

    @Test func deleteKeepsTheLanguageShown() {
        type("gksrnr")
        session.handle(.delete, client: field)
        session.handle(.delete, client: field)
        #expect(field.text == "한ㄱ")
        type(" ")
        #expect(field.text == "한ㄱ ")
    }

    @Test func deleteEnglishKeyByKey() {
        type("hello")
        session.handle(.delete, client: field)
        #expect(field.text == "hell")
    }
}

@MainActor @Suite struct MixedWordSessionTests {
    let field = FakeTextField()

    func type(_ session: InputSession, _ s: String) {
        for ch in s {
            let handled = ch.isASCII && ch.isLetter ? session.handle(.letter(ch), client: field)
                                                    : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    func session(japanese: Bool = false) -> InputSession {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-mixed-\(UUID().uuidString).json")
        let base = japanese ? SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter) : splitting
        return InputSession(engine: LearningEngine(base: base, storeURL: url), policies: .escSwitches, japaneseEnabled: japanese)
    }

    /// The English + Korean word split is what gets typed, not only what the engine decides.
    @Test func typesEnglishThenKoreanWord() {
        type(session(), "hellodnjfem githubtjqj ")
        #expect(field.text == "hello월드 github서버 ")
    }

    /// Return on an underlined word only confirms it; with nothing underlined it is the app's.
    @Test func returnConfirmsThenGoesToTheApp() {
        let session = session()
        type(session, "dkssud")
        #expect(session.handle(.enter, client: field))
        #expect(field.text == "안녕" && field.marked.location == NSNotFound)
        #expect(!session.handle(.enter, client: field))
    }

    /// By default Esc isn't a switch key: the word goes in as shown and the app gets the Esc,
    /// also right after a commit. The chosen keys (`.cycle`) still switch.
    @Test func escGoesToTheAppUnlessChosen() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-esc-\(UUID().uuidString).json")
        let session = InputSession(engine: LearningEngine(base: sharedEngine, storeURL: url))
        #expect(session.policy.switchKeys == [.rightOption, .shiftEscape])
        type(session, "dkssud")
        #expect(!session.handle(.escape, client: field))
        #expect(field.text == "안녕" && field.marked.location == NSNotFound)
        type(session, " ")
        #expect(!session.handle(.escape, client: field))
        #expect(field.text == "안녕 ")
        #expect(session.handle(.cycle, client: field)) // nothing to change: dropped
        type(session, "dkssud ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "안녕 dkssud ")
    }

    /// With the setting off, Return confirms the word and the app gets it too.
    @Test func returnGoesOnWhenItDoesntOnlyConfirm() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-return-\(UUID().uuidString).json")
        let session = InputSession(engine: LearningEngine(base: sharedEngine, storeURL: url), returnConfirmsOnly: false)
        type(session, "dkssud")
        #expect(!session.handle(.enter, client: field))
        #expect(field.text == "안녕" && field.marked.location == NSNotFound)
    }

    /// A single letter with a particle (a variable name, an axis) is typed as such.
    @Test func typesSingleLetterWithParticle() {
        type(session(), "xdp ndl Xfmf Xeh ")
        #expect(field.text == "x에 n이 X를 X도 ")
    }

    /// Short English ending in the keys of 도 or 나 stays English.
    @Test func keepsShortEnglishEndingInEhOrSk() {
        type(session(), "heh meh tsk ")
        #expect(field.text == "heh meh tsk ")
    }

    /// Korean then romaji with no space: the Korean goes in, the rest is a Japanese word.
    @Test func typesKoreanThenJapaneseWord() {
        type(session(japanese: true), "qusruddlfurrireki dlfurrireki ")
        #expect(field.text == "변경이력りれき 이력りれき ")
    }

    /// A Japanese word with a Korean particle: the word as Japanese, the particle as Korean.
    @Test func typesJapaneseWordThenParticle() {
        type(session(japanese: true), "duwjsgl rirekifmf rirekidptj ")
        #expect(field.text == "여전히 りれき를 りれき에서 ")
    }

    /// A Japanese phrase with a Korean word straight after it.
    @Test func typesJapaneseThenKoreanWord() {
        type(session(japanese: true), "kyouhaehtlfkrdms ")
        #expect(field.text == "きょうは도시락은 ")
    }

    /// Korean then English with no space: 오늘은 then google에서.
    @Test func typesKoreanThenEnglishWord() {
        type(session(japanese: true), "dhsmfdmsgoogledptj dlrjtdmsgithubdp ")
        #expect(field.text == "오늘은google에서 이것은github에 ")
    }

    @Test func plainKoreanStaysWhole() {
        type(session(japanese: true), "dkssudgktpdy qusruddlfur rhkswjadmfh ")
        #expect(field.text == "안녕하세요 변경이력 관점으로 ")
        // A consonant just typed for the next syllable isn't broken Hangul (하느님ㅇ, then lad…).
        field.text = ""; field.cursor = 0
        type(session(japanese: true), "gksmsladml tlsqnsladms godirpTspdy ")
        #expect(field.text == "하느님의 신부님은 해야겠네요 ")
    }
}
