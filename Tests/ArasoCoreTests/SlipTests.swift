import Foundation
import Testing
@testable import ArasoCore

/// One slip of the fingers in a Korean word (#85): what it could have been (`SlipGuesser`), listed on a
/// long press of the switch key, and put in at the word's end where the keys can't be Korean as typed
/// (`fixSlips`); Delete right after undoes that, and what the user leaves is learned.
@MainActor @Suite struct SlipTests {
    let field = FakeTextField()
    let dictionary: DictionaryEngine
    let session: InputSession
    let guesser = SlipGuesser()

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-slip-\(UUID().uuidString).json")
        dictionary = DictionaryEngine(base: SplittingEngine(base: trilingual, english: trilingual.english,
                                                            japanese: trilingual.segmenter), storeURL: url)
        session = InputSession(engine: dictionary, policies: .escSwitches, fixSlips: true)
        session.activate(app: "com.apple.TextEdit")
    }

    /// "⏎" Return, "⎋" Esc, "⌫" Delete, "⌥" a switch key, "◆" the long press, "↓" "↑"; the app types
    /// what is passed on (Delete: the character before the caret).
    func type(_ script: String, into session: InputSession? = nil) {
        let session = session ?? self.session
        for ch in script {
            let key: InputSession.Key
            switch ch {
            case "⏎": key = .enter
            case "⎋": key = .escape
            case "⌫": key = .delete
            case "⌥": key = .cycle
            case "◆": key = .guess
            case "↓": key = .down
            case "↑": key = .up
            case let c where c.isLetter: key = .letter(c)
            default: key = .printable(ch)
            }
            defer { field.caretCaughtUp() }
            // Terminal takes these itself with nothing marked: the input method never sees them.
            let appsOwn = field.keysOnlyWhileMarked && field.markedRange().location == NSNotFound
                && [.escape, .delete, .enter, .up, .down].contains(key)
            guard appsOwn || !session.handle(key, client: field) else { continue }
            switch key {
            case .escape: field.insertText("^[", replacing: nil)
            case .enter: field.insertText("\n", replacing: nil)
            case .delete:
                let caret = field.selectedRange().location
                if caret > 0 { field.insertText("", replacing: NSRange(location: caret - 1, length: 1)) }
            case .printable(let c): field.insertText(String(c), replacing: nil)
            default: break
            }
        }
    }

    // MARK: - Guesses

    @Test func undoesEachKindOfSlip() {
        #expect(guesser.guesses(for: "clekkr").first?.text == "치다가") // swapped
        #expect(guesser.guesses(for: "rkatkgkqslekj").first?.text == "감사합니다") // a key too many
        #expect(guesser.guesses(for: "gotdjdy").first?.text == "했어요") // Shift let go too soon
        #expect(guesser.guesses(for: "djddj").first?.text == "영어") // the key next to it
        #expect(guesser.guesses(for: "dlrj").contains { $0.text == "이건" }) // a key left out
    }

    @Test func listsAtMostFiveAndNeverTheWordAsTyped() {
        let guesses = guesser.guesses(for: "dlrj")
        #expect(guesses.count <= SlipGuesser.limit)
        #expect(!guesses.contains { $0.text == "이거" })
    }

    @Test func countsNeighboursOnTheKeys() {
        #expect(Set(SlipGuesser.neighbors(of: "j")) == Set("hkuinm"))
        #expect(SlipGuesser.neighbors(of: "Q").contains("W")) // ㅃ's neighbour keeps Shift where it is ㅉ
        let colemak = LatinLayout.$override.withValue(.colemak) { guesser.guesses(for: "cifeep").first?.text }
        #expect(colemak == "치다가") // clekkr typed on Colemak: the same keys, two swapped
    }

    @Test func fixesOnlyWordsThatCantBeKoreanAsTyped() {
        #expect(guesser.autoFix("clekkr", afterKorean: true)?.text == "치다가")
        #expect(guesser.autoFix("gotdjdy", afterKorean: true)?.text == "했어요") // syllables only, but Shift
        #expect(guesser.autoFix("djddj", afterKorean: true) == nil) // 엉어 reads as syllables: only listed
        #expect(guesser.autoFix("tbody", afterKorean: true) == nil) // English could have it
        #expect(guesser.autoFix("rhakdnjb", afterKorean: true) == nil) // 고마워ㅠ: chat jamo
        #expect(guesser.autoFix("dlrj", afterKorean: true) == nil) // too short
    }

    @Test func marksWhatAGuessChanged() {
        #expect(SlipGuesser.changed(from: "엉어", to: "영어") == 0..<1)
        #expect(SlipGuesser.changed(from: "누ㅜ를", to: "누구를") == 1..<2)
        #expect(SlipGuesser.changed(from: "치다ㅏㄱ", to: "치다가") == 2..<3)
        #expect(SlipGuesser.changed(from: "안녕ㄱ", to: "안녕").isEmpty)
    }

    @Test func shiftIsFixedOnFinalsOnly() {
        #expect(guesser.autoFix("ckftmdPdy", afterKorean: true) == nil) // 찰스예요, not 에요
        #expect(guesser.autoFix("tlwkrgksmsrjdPdy", afterKorean: true) == nil) // 시작하는거예요
        #expect(guesser.autoFix("ekfktj", afterKorean: true) == nil) // 다라서 is only listed (따라서)
    }

    @Test func twoSyllablesAtTheStartButThreeAfterEnglish() {
        #expect(guesser.autoFix("gksrrn", afterKorean: true)?.text == "한국")
        #expect(guesser.autoFix("gksrrn", afterKorean: false) == nil)
        type("gksrrn ")
        #expect(field.text == "한국 ") // nothing before it counts as Korean
    }

    // MARK: - At the word's end

    @Test func aBrokenWordGoesInAsTheWordMeant() {
        type("Qkfmrp clekkr qhaus ")
        #expect(field.text == "빠르게 치다가 보면 ")
    }

    @Test func offLeavesItAsTyped() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-slip-\(UUID().uuidString).json")
        let plain = InputSession(engine: DictionaryEngine(base: SplittingEngine(base: trilingual, english: trilingual.english,
                                                                               japanese: trilingual.segmenter), storeURL: url),
                                 policies: .escSwitches)
        type("Qkfmrp clekkr ", into: plain)
        #expect(field.text == "빠르게 clekkr ")
    }

    @Test func wordsTypedRightStayAsTheyAre() {
        type("dlrjs tbody xorm rhakdnjb qkRnqslek xoqdl sksnlqslek aksemfa ")
        #expect(field.text == "이건 tbody 태그 고마워ㅠ 바꿉니다 탭이 나뉩니다 만듦 ") // stems with an ending the lists lack
    }

    @Test func deleteRightAfterUndoesTheFixAndKeepsTheSpace() {
        type("Qkfmrp clekkr ⌫")
        #expect(field.text == "빠르게 clekkr ")
        type("⌫")
        #expect(field.text == "빠르게 clekkr") // then Delete is the app's again
    }

    @Test func aFixUndoneByMistakeIsPickedAgainFromTheList() {
        type("Qkfmrp clekkr ⌫◆")
        #expect(field.text == "빠르게 치다가 ")
        type("⏎")
        #expect(dictionary.correctedOnce("clekkr", app: nil) == nil)
        type("⌫") // picked by hand: Delete is the app's now
        #expect(field.text == "빠르게 치다가")
        type("qhaus ")
        #expect(dictionary.correctedOnce("clekkr", app: nil) == nil)
        #expect(dictionary.rememberedLanguage("clekkr", app: nil) == nil)
    }

    @Test func anUndoneFixLeftAsItIsIsntMadeAgain() {
        type("Qkfmrp clekkr ⌫qhaus ")
        #expect(dictionary.correctedOnce("clekkr", app: nil) == .english)
        type("clekkr ")
        #expect(field.text.hasSuffix("보면 clekkr "))
    }

    @Test func anUndoneFixDeletedIntoTeachesNothing() {
        type("Qkfmrp clekkr ⌫⌫⌫⌫")
        #expect(dictionary.correctedOnce("clekkr", app: nil) == nil)
        #expect(dictionary.rememberedLanguage("clekkr", app: nil) == nil)
    }

    @Test func switchingAFixAwayIsLearnedToo() {
        type("Qkfmrp clekkr ⌥x")
        #expect(field.text.hasPrefix("빠르게 clekkr "))
        #expect(dictionary.correctedOnce("clekkr", app: nil) == .english)
    }

    @Test func aFixSwitchedBackLaterIsLearned() {
        type("Qkfmrp clekkr qhaus ")
        field.cursor = 5 // in 치다가
        type("⌥⏎")
        #expect(field.text == "빠르게 clekkr 보면 ")
        #expect(dictionary.correctedOnce("clekkr", app: nil) == .english)
    }

    @Test func theLongPressWhileFixingDoesNothing() {
        type("Qkfmrp clekkr qhaus ")
        field.cursor = 5
        type("⌥")
        let marked = field.text
        type("◆")
        #expect(field.text == marked)
        #expect(session.fixing != nil)
        #expect(session.guesses == nil)
    }

    @Test func aFixLeftInPlaceTeachesNothing() {
        type("Qkfmrp clekkr qhaus ")
        #expect(dictionary.correctedOnce("clekkr", app: nil) == nil)
        #expect(dictionary.rememberedLanguage("clekkr", app: nil) == nil)
    }

    // MARK: - The long press

    @Test func longPressListsGuessesAndShowsTheFirst() {
        type("djddj ◆")
        #expect(field.text == "영어 ")
        #expect(session.guesses?.texts.first == "영어")
        #expect(session.guesses?.changed.first == 0..<1)
        type("↓")
        #expect(field.text == session.guesses.map { $0.texts[1] + " " })
        type("⎋")
        #expect(field.text == "엉어 ")
        #expect(session.guesses == nil)
    }

    @Test func aDigitPicksAndTheNextWordGoesOn() {
        type("djddj ◆2")
        let second = field.text
        #expect(second != "엉어 " && second != "영어 ")
        type("vks ")
        #expect(field.text == second + "판 ")
    }

    @Test func returnKeepsTheGuessAndTeachesNothing() {
        type("djddj ◆⏎")
        #expect(field.text == "영어 ")
        #expect(dictionary.correctedOnce("djddj", app: nil) == nil)
    }

    @Test func aWordBeingTypedGoesInFirst() {
        type("djddj◆")
        #expect(field.text == "영어")
        #expect(session.guesses != nil)
    }

    @Test func nothingToGuessSaysSo() {
        type("zzzz ")
        let before = field.text
        type("◆")
        #expect(field.text == before)
        #expect(session.guesses?.texts.isEmpty == true)
    }

    @Test func pickingAGuessForgetsAFixUndone() {
        type("Qkfmrp clekkr ⌫qhaus ")
        #expect(dictionary.correctedOnce("clekkr", app: nil) != nil)
        type("clekkr ◆⏎")
        #expect(field.text.hasSuffix("치다가 "))
        #expect(dictionary.correctedOnce("clekkr", app: nil) == nil)
        #expect(session.learned?.learning == .forgot)
        type("x clekkr ")
        #expect(field.text.hasSuffix("치다가 "))
    }

    // MARK: - The long press in Terminal

    /// As Terminal is, real keys: Esc, Delete, Return and the arrows reach the input method only with
    /// text marked, and the caret reported right after an insert hasn't moved yet.
    func likeTerminal() {
        field.keysOnlyWhileMarked = true
        field.caretLags = true
    }

    @Test func inTerminalEscPutsBackAWordAfterSpace() {
        likeTerminal()
        type("djddj ◆")
        #expect(field.text == "영어 ")
        #expect(field.markedRange().location == 0) // so that Esc comes to the input method
        #expect(session.guesses?.texts.first == "영어")
        type("⎋")
        #expect(field.text == "엉어 ")
        #expect(field.markedRange().location == NSNotFound)
        #expect(session.guesses == nil)
    }

    @Test func inTerminalAWordBeingTypedListsGuesses() {
        likeTerminal()
        type("djddj◆")
        #expect(field.text == "영어")
        #expect(session.guesses?.texts.first == "영어")
        #expect(field.insertions.isEmpty) // never went in just to be taken away
        type("⏎")
        #expect(field.text == "영어")
        #expect(field.markedRange().location == NSNotFound)
        #expect(session.guesses == nil)
    }

    @Test func inTerminalEscPutsBackAWordBeingTyped() {
        likeTerminal()
        type("djddj◆⎋")
        #expect(field.text == "엉어")
        #expect(field.markedRange().location == NSNotFound)
        type("⌥") // the word just committed, as after Return
        #expect(field.text == "djddj")
    }

    @Test func inTerminalTheListStepsAndADigitPicks() {
        likeTerminal()
        type("djddj ◆↓")
        let second = session.guesses!.texts[1]
        #expect(field.text == second + " ")
        #expect(field.markedRange().location == 0)
        type("1")
        #expect(field.text == "영어 ")
        #expect(field.markedRange().location == NSNotFound)
        #expect(session.guesses == nil)
    }

    @Test func inTerminalTheNextWordKeepsTheGuess() {
        likeTerminal()
        type("djddj ◆vks ")
        #expect(field.text == "영어 판 ")
        #expect(field.markedRange().location == NSNotFound)
    }

    @Test func inTerminalLeavingKeepsTheGuess() {
        likeTerminal()
        type("djddj ◆")
        #expect(session.commandPressed(client: field, heldWordOnly: false))
        #expect(field.text == "영어 ")
        #expect(field.markedRange().location == NSNotFound)
        type("djddj ◆")
        session.commit(client: field) // focus moves
        #expect(field.text == "영어 영어 ")
        #expect(field.markedRange().location == NSNotFound)
    }

    @Test func nothingToGuessInTerminalJustConfirms() {
        likeTerminal()
        type("zzzz◆")
        #expect(field.text == "zzzz" || field.text == "ㅋㅋㅋㅋ")
        #expect(field.markedRange().location == NSNotFound)
        #expect(session.guesses?.texts.isEmpty == true)
    }

    @Test func aCaretThatLagsElsewhereBreaksNothing() {
        field.caretLags = true // another terminal, not known to need marked text
        type("djddj◆")
        #expect(field.text == "엉어")
        #expect(session.guesses?.texts.isEmpty == true) // says so, the word left as it went in
    }

    // MARK: - The long press where the field can't be read

    /// As Ghostty is, real keys: the caret is always at the start, and no text comes back.
    func likeGhostty() {
        field.readable = false
        field.caretStaysAtStart = true
    }

    @Test func inGhosttyAWordBeingTypedListsGuesses() {
        likeGhostty()
        type("djddj◆")
        #expect(field.text == "영어")
        #expect(session.guesses?.texts.first == "영어")
        #expect(field.markedRange().location != NSNotFound)
        type("⏎")
        #expect(field.text == "영어")
        #expect(field.markedRange().location == NSNotFound)
    }

    @Test func inGhosttyEscPutsBackAWordBeingTyped() {
        likeGhostty()
        type("djddj◆⎋")
        #expect(field.text == "엉어")
        #expect(field.markedRange().location == NSNotFound)
    }

    @Test func inGhosttyTheNextWordKeepsTheGuess() {
        likeGhostty()
        type("djddj◆ ")
        #expect(field.text == "영어 ")
        #expect(field.markedRange().location == NSNotFound)
    }

    @Test func inGhosttyAWordAlreadyInIsLeftAlone() {
        likeGhostty()
        type("djddj ◆")
        #expect(field.text == "엉어 ")
        #expect(field.markedRange().location == NSNotFound)
        #expect(session.guesses?.texts.isEmpty == true)
    }

    @Test func aHeldWordGoesInAndSaysSo() {
        likeGhostty()
        let held = InputSession(engine: dictionary, policies: AppPolicies(overrides: ["test.hold": .init(holdSpace: true)]))
        held.activate(app: "test.hold")
        type("djddj ◆", into: held)
        #expect(field.text == "엉어 ")
        #expect(field.markedRange().location == NSNotFound)
        #expect(held.guesses?.texts.isEmpty == true)
    }
}
