import Foundation
import Testing
@testable import SeamtypeCore

/// An app set to hold Space (`AppPolicy.holdSpace`, for terminals): the word stays underlined with
/// its space until the next word starts, so Esc still changes it and Delete takes back only the space.
@MainActor @Suite struct HoldSpaceTests {
    let field = FakeTextField()
    let learning: LearningEngine
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-hold-\(UUID().uuidString).json")
        learning = LearningEngine(base: splitting, storeURL: url)
        session = InputSession(engine: learning, policies: AppPolicies(overrides: ["test.hold": .init(holdSpace: true)]))
        session.activate(app: "test.hold")
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

    /// The underlined text, nil when nothing is underlined.
    var marked: String? {
        guard field.marked.location != NSNotFound else { return nil }
        return (field.text as NSString).substring(with: field.marked)
    }

    @Test func spaceKeepsTheWordUnderlinedWithItsSpace() {
        #expect(type("dkssud ").last == true)
        #expect(field.text == "안녕 ")
        #expect(marked == "안녕 ")
    }

    @Test func theNextWordCommitsTheHeldOne() {
        type("dkssud gktpdy")
        #expect(field.text == "안녕 하세요")
        #expect(marked == "하세요")
        type(" ")
        #expect(marked == "하세요 ")
    }

    @Test func deleteTakesBackOnlyTheSpace() {
        type("dkssud ")
        #expect(session.handle(.delete, client: field))
        #expect(field.text == "안녕" && marked == "안녕")
        // Delete again: the word itself, as while typing.
        #expect(session.handle(.delete, client: field))
        #expect(field.text == "안녀")
    }

    /// What this is for: Space pressed before looking, then Delete and ⇧Esc.
    @Test func deleteThenShiftEscChangesTheWord() {
        type("dkssud ")
        session.handle(.delete, client: field)
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "dkssud" && marked == "dkssud")
        type(" ")
        #expect(field.text == "dkssud " && marked == "dkssud ")
        type("x")
        #expect(field.text.hasPrefix("dkssud "))
        #expect(field.marked.location == ("dkssud " as NSString).length)
    }

    @Test func escRightAfterSpaceChangesTheWordAndKeepsTheSpace() {
        type("dkssud ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "dkssud " && marked == "dkssud ")
        #expect(session.handle(.escape, client: field))
        #expect(field.text == "안녕 " && marked == "안녕 ")
    }

    /// What is shown after Space is what would have been committed: the whole word's decision,
    /// not the preview of its last keystroke.
    @Test(arguments: ["go", "so", "did", "hello", "dkssud", "githubdp", "rjtm", "dhsmf", "wkqtm", "gst", "APIfmf"])
    func heldWordReadsAsItWouldCommit(keys: String) {
        let plain = FakeTextField()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-hold-plain-\(UUID().uuidString).json")
        let standard = InputSession(engine: LearningEngine(base: splitting, storeURL: url))
        for ch in keys { standard.handle(.letter(ch), client: plain) }
        standard.handle(.printable(" "), client: plain) // the app would type the space
        type(keys + " ")
        #expect(field.text == plain.text + " ")
    }

    @Test func returnCommitsTheHeldWordWithItsSpaceAndOnlyConfirms() {
        type("dkssud ")
        #expect(session.handle(.enter, client: field))
        #expect(field.text == "안녕 " && marked == nil)
        #expect(!session.handle(.enter, client: field))
    }

    @Test func otherKeysCommitTheHeldWordWithItsSpace() {
        type("dkssud ")
        #expect(!session.handle(.other, client: field))
        #expect(field.text == "안녕 " && marked == nil)
    }

    @Test func aSecondSpaceAndPunctuationGoToTheApp() {
        type("dkssud  ")
        #expect(field.text == "안녕  " && marked == nil)
        type("gktpdy .")
        #expect(field.text == "안녕  하세요 ." && marked == nil)
    }

    @Test func losingFocusCommitsTheHeldWordWithItsSpace() {
        type("dkssud ")
        session.commit(client: field)
        #expect(field.text == "안녕 " && marked == nil)
    }

    @Test func escWhileHeldIsLearnedWhenTheWordGoesIn() {
        type("hello ")
        session.handle(.cycle, client: field)
        #expect(field.text == "ㅗ디ㅣㅐ ")
        #expect(learning.pending.isEmpty)
        type("x")
        #expect(learning.pending == ["hello": .korean])
    }

    /// A held word is still the word being typed: switched to Japanese, Space converts it.
    @Test func spaceOnAHeldWordSwitchedToJapaneseConverts() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-hold-ja-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: url)
        let japanese = InputSession(engine: engine, policies: AppPolicies(overrides: ["test.hold": .init(holdSpace: true)]),
                                    converter: FakeConverter(), japaneseEnabled: true)
        japanese.activate(app: "test.hold")
        let field = FakeTextField()
        for ch in "hello" { japanese.handle(.letter(ch), client: field) }
        japanese.handle(.printable(" "), client: field)
        #expect(field.text == "hello ")
        japanese.handle(.cycle, client: field)
        #expect(field.text == "へっぉ ")
        #expect(japanese.handle(.printable(" "), client: field))
        #expect(japanese.conversion != nil)
        #expect(field.text == "へっぉ")
    }

    @Test func otherAppsFinishTheWordOnSpace() {
        session.activate(app: "com.example.editor")
        #expect(type("dkssud ").last == false)
        #expect(field.text == "안녕 " && marked == nil)
    }
}
