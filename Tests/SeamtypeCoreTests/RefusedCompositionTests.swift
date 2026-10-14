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

/// A composing field (a `FakeTextField` underneath) that also asks for a commit whenever its
/// marked text is cleared.
final class CommittingWhenClearedTextField: TextClient {
    let inner = FakeTextField()
    var onClear: () -> Void = {}
    var text: String { inner.text }

    func setMarkedText(_ s: String) {
        inner.setMarkedText(s)
        if s.isEmpty { onClear() }
    }
    func setMarkedText(_ s: String, replacing range: NSRange) { inner.setMarkedText(s, replacing: range) }
    func insertText(_ s: String, replacing range: NSRange?) { inner.insertText(s, replacing: range) }
    func selectedRange() -> NSRange { inner.selectedRange() }
    func markedRange() -> NSRange { inner.markedRange() }
    func text(in range: NSRange) -> String? { inner.text(in: range) }
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

    /// A field that asks for a commit while the marked text is cleared (nothing typed) isn't
    /// refusing composition: the next word is still decided.
    @Test func aCommitWhileClearingIsNotARefusal() {
        let composing = CommittingWhenClearedTextField()
        composing.onClear = { [session] in session.clientRefusedComposition(client: composing) }
        type("hello", into: composing) { composing.insertText($0, replacing: nil) }
        for _ in 0..<5 { _ = session.handle(.delete, client: composing) }
        #expect(composing.text == "")
        #expect(!session.compositionRefused)
        type("dkssud ", into: composing) { composing.insertText($0, replacing: nil) }
        #expect(composing.text == "안녕 ")
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
