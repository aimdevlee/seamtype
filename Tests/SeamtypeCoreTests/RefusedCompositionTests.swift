import Foundation
import Testing
@testable import SeamtypeCore

/// A text field that won't hold marked text: it answers `setMarkedText` by asking for the
/// composition to be committed (KakaoTalk's masked password field does, on every key) and
/// takes inserted text only; it reports neither a caret nor its text.
final class UncomposingTextField: TextClient {
    var text = ""
    var markedCalls = 0
    /// Refuses from this call of `setMarkedText` on (the first by default).
    var refusesFrom = 1
    var refuse: () -> Void = {}

    func setMarkedText(_ s: String) {
        markedCalls += 1
        if markedCalls >= refusesFrom { refuse() }
    }
    func setMarkedText(_ s: String, replacing range: NSRange) { setMarkedText(s) }
    func insertText(_ s: String, replacing range: NSRange?) { text += s }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func markedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func text(in range: NSRange) -> String? { nil }
}

/// A field that commits the composition as soon as it is set gets its keys as typed.
@MainActor @Suite struct RefusedCompositionTests {
    let field = UncomposingTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-refused-\(UUID().uuidString).json")
        session = InputSession(engine: LearningEngine(base: sharedEngine, storeURL: url))
        session.activate(app: "test.app")
        field.refuse = { [session, field] in session.clientRefusedComposition(client: field) }
    }

    /// Types letters, digits and spaces; keys the session passes on are typed by the field.
    func type(_ s: String, into client: TextClient & AnyObject, insert: (String) -> Void) {
        for ch in s {
            let key: InputSession.Key = ch.isLetter ? .letter(ch) : .printable(ch)
            if !session.handle(key, client: client) { insert(String(ch)) }
        }
    }

    @Test func passwordGoesInAsTyped() {
        type("Password123!", into: field) { field.text += $0 }
        #expect(field.text == "Password123!")
        #expect(session.compositionRefused)
        #expect(session.keys.isEmpty)
    }

    @Test func keysThatReadAsKoreanStayAsTyped() {
        type("dkssud gktpdy", into: field) { field.text += $0 }
        #expect(field.text == "dkssud gktpdy")
    }

    @Test func refusalMidWordKeepsTheTypedKeys() {
        field.refusesFrom = 3 // Pa shown, then the field gives up on Pas
        type("Password", into: field) { field.text += $0 }
        #expect(field.text == "Password")
    }

    @Test func theNextFieldComposesAgain() {
        type("dkssud", into: field) { field.text += $0 }
        #expect(field.text == "dkssud")
        let next = FakeTextField()
        session.activate(app: "test.app")
        #expect(!session.compositionRefused)
        type("dkssud ", into: next) { next.insertText($0, replacing: nil) }
        #expect(next.text == "안녕 ")
    }
}
