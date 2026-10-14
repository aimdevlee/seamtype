import Foundation
import Testing
@testable import SeamtypeCore

/// A terminal left at the default policy (Esc switches language), through a real session, with
/// vim reporting its modes.
@MainActor @Suite struct VimSessionTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-vim-\(UUID().uuidString).json")
        session = InputSession(engine: LearningEngine(base: sharedEngine, storeURL: url), policies: .escSwitches)
        session.activate(app: "test.terminal")
    }

    /// Types `script` ("⎋" Esc, "⏎" Return) and returns the keys the app got straight.
    @discardableResult
    func type(_ script: String) -> String {
        var passed = ""
        for ch in script {
            let key: InputSession.Key
            switch ch {
            case "⎋": key = .escape
            case "⏎": key = .enter
            case let c where c.isASCII && c.isLetter: key = .letter(c)
            default: key = .printable(ch)
            }
            if !session.handle(key, client: field) {
                passed.append(ch)
                if ch != "⎋" { field.insertText(ch == "⏎" ? "\n" : String(ch), replacing: nil) }
            }
        }
        return passed
    }

    @Test func normalModeKeysGoStraightThrough() {
        session.vimChanged(to: .normal, client: field) // VimEnter, before any Esc
        #expect(type("sddciw:wq⏎") == "sddciw:wq⏎")
        #expect(field.marked.location == NSNotFound)
    }

    @Test func wordsAreDecidedInInsertMode() {
        session.vimChanged(to: .normal, client: field)
        type("o")
        session.vimChanged(to: .insert, client: field)
        type("dkssud ")
        #expect(field.text == "o안녕 ")
    }

    @Test func escCommitsTheWordThenVimSaysNormal() {
        session.vimChanged(to: .insert, client: field)
        type("dkssud⎋")
        #expect(field.text == "안녕")
        session.vimChanged(to: .normal, client: field) // InsertLeave
        #expect(type("dd") == "dd")
    }

    @Test func keysAreHeldUntilVimSaysInsert() {
        // A mapping that enters insert mode is seen only when vim says so.
        session.vimChanged(to: .normal, client: field)
        #expect(type(" i") == " i")
        session.vimChanged(to: .insert, client: field)
        #expect(type("dkssud") == "")
    }

    @Test func leavingVimGivesTheShellWordsBack() {
        session.vimChanged(to: .normal, client: field)
        type(":wq⏎")
        session.vimChanged(to: .off, client: field) // VimLeavePre
        type("dkssud ")
        #expect(field.text.hasSuffix("안녕 "))
    }

    @Test func shiftEscStartsDecidingWordsAgain() {
        session.vimChanged(to: .normal, client: field)
        #expect(session.handle(.cycle, client: field))
        #expect(!session.inVimNormalMode)
        type("dkssud ")
        #expect(field.text == "안녕 ")
    }

    @Test func comingBackToTheTerminalKeepsVimsMode() {
        session.vimChanged(to: .normal, client: field)
        session.activate(app: "test.terminal")
        #expect(type("dd") == "dd")
    }

    @Test func escIsVimsWhileVimReportsEvenWhereEscSwitchesLanguage() {
        session.vimChanged(to: .insert, client: field)
        #expect(type("dkssud⎋") == "⎋")
        #expect(field.text == "안녕")
        // Right after a committed word too: Esc leaves insert mode instead of flipping the word.
        type(" ")
        session.vimChanged(to: .insert, client: field)
        #expect(type("dkssud ⎋") == " ⎋")
        #expect(field.text == "안녕 안녕 ")
    }

    @Test func withoutVimEscStillSwitchesLanguage() {
        #expect(type("dkssud⎋") == "")
        #expect(field.text == "dkssud")
    }

    @Test func anotherAppForgetsVim() {
        session.vimChanged(to: .normal, client: field)
        session.activate(app: "test.other")
        #expect(!session.inVimNormalMode)
    }
}
