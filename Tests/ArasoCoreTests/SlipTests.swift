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
            guard !session.handle(key, client: field) else { continue }
            switch key {
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
}
