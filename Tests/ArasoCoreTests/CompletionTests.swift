import Foundation
import Testing
@testable import ArasoCore

@Suite struct CompletionTests {
    @Test func completesKoreanByCount() {
        #expect(Completion.suggest("안녕하", as: .korean).first == "안녕하세요")
        #expect(Completion.suggest("안녕하", as: .korean).contains("안녕하십니까"))
    }

    @Test func lastSyllableMayStillTakeAFinal() {
        #expect(Completion.suggest("감사하", as: .korean).first == "감사합니다")
    }

    @Test func completesEnglishFromTwoLettersKeepingTheCaseTyped() {
        #expect(Completion.suggest("becau", as: .english).first == "because")
        #expect(Completion.suggest("Becau", as: .english).first == "Because")
        #expect(!Completion.suggest("be", as: .english).isEmpty)
        #expect(Completion.suggest("be", as: .english).count <= Completion.limit)
    }

    @Test func tooShortOrNotAWordGetsNothing() {
        #expect(Completion.suggest("안", as: .korean).isEmpty)
        #expect(Completion.suggest("b", as: .english).isEmpty)
        #expect(Completion.suggest("안녕ㅎ", as: .korean).isEmpty)
        #expect(Completion.suggest("abc", as: .japanese).isEmpty)
    }

    @Test func textAlreadyWrittenComesFirstSentenceThenWord() {
        let context = "회의는 내일 오후 세시에 합니다. 다른 얘기\n"
        let korean = Completion.suggest("오후", as: .korean, context: context)
        #expect(korean.first == "오후 세시에 합니다.")
        #expect(!korean.contains("오후")) // already what is typed
        let english = "We should refactor the parser first. Then ship."
        let got = Completion.suggest("ref", as: .english, context: english)
        #expect(Array(got.prefix(2)) == ["refactor the parser first.", "refactor"])
    }

    @Test func paddedBoxedScreenKeepsItsSentences() {
        let pad = String(repeating: " ", count: 300)
        let raw = "  ⏺ 원인을 찾았습니다." + pad + "\n" + pad + "\n       │❯\u{a0}" + pad + "\n───────────" + pad
        let screen = Completion.tidyScreen(raw)
        #expect(screen == "⏺ 원인을 찾았습니다.\n❯")
        #expect(Completion.suggest("원인", as: .korean, context: screen).first == "원인을 찾았습니다.")
    }

    @Test func theBoxBeingTypedInIsLeftOut() {
        let edge = String(repeating: "─", count: 30)
        let raw = "⏺ 오늘 배포는 끝났습니다.\n" + edge + "\n❯ 오늘 저녁에 다시\n이어서 쓰는 줄\n" + edge + "\n  ⏵⏵ auto mode on"
        let caret = (raw as NSString).range(of: "다시").location
        let screen = Completion.tidyScreen(raw, caret: caret)
        #expect(!screen.contains("저녁"))
        #expect(!screen.contains("이어서"))
        #expect(Completion.suggest("오늘", as: .korean, context: screen).first == "오늘 배포는 끝났습니다.")
    }

    @Test func outsideABoxOnlyTheCaretsLineGoes() {
        let raw = "첫 줄입니다.\n$ git commit -m 지금 쓰는\n"
        let caret = (raw as NSString).range(of: "쓰는").location
        #expect(Completion.tidyScreen(raw, caret: caret) == "첫 줄입니다.")
    }

    @Test func theSentenceBeingTypedIsNotItsOwnSuggestion() {
        #expect(Completion.beforeSentence("앞 문장입니다. 지금 쓰는 문장") == "앞 문장입니다.")
        #expect(Completion.beforeSentence("한 줄\n지금 쓰는") == "한 줄\n")
        #expect(Completion.beforeSentence("지금 쓰는") == "")
    }

    @Test func wideCellFillersAreDropped() {
        let iterm = "원\u{0}인\u{0}을\u{0} 찾\u{0}았\u{0}습\u{0}니\u{0}다\u{0}."
        #expect(Completion.tidyScreen(iterm) == "원인을 찾았습니다.")
        #expect(Completion.suggest("원인", as: .korean, context: iterm).first == "원인을 찾았습니다.")
    }

    @Test func usualWordsComeFirstAndASentenceOnlyOnceTypedTwice() {
        let history = TypedHistory(url: nil)
        history.noteWord("감사드려요")
        history.noteSentence("감사 인사 드립니다.")
        #expect(Completion.suggest("감사", as: .korean, history: history).first == "감사드려요")
        history.noteSentence("감사 인사 드립니다.")
        #expect(Completion.suggest("감사", as: .korean, history: history).prefix(2) == ["감사 인사 드립니다.", "감사드려요"])
    }

    @Test func moreUsedOutranksOlder() {
        let history = TypedHistory(url: nil), old = Date(timeIntervalSinceNow: -60 * 86_400)
        for _ in 0..<3 { history.noteWord("deploy", now: old) }
        history.noteWord("debug")
        #expect(Completion.suggest("de", as: .english, history: history).prefix(2) == ["debug", "deploy"])
    }

    @Test func repeatedOnScreenComesBeforeLatest() {
        #expect(Completion.byCount(["b", "a", "c", "a"]) == ["a", "b", "c"])
    }

    @Test func sentencesComeBeforeWordsLatestFirst() {
        let context = "deploy staging. deploy production now."
        let got = Completion.suggest("dep", as: .english, context: context)
        #expect(Array(got.prefix(3)) == ["deploy production now.", "deploy staging.", "deploy"])
    }
}

@MainActor @Suite struct SuggestionSessionTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-session-\(UUID().uuidString).json")
        session = InputSession(engine: DictionaryEngine(base: sharedEngine, storeURL: url), policies: .escSwitches)
    }

    func type(_ s: String) {
        for ch in s {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    @Test func tabStepsThroughTheSuggestionsAndTheNextKeyCommits() {
        type("dkssudgk")
        #expect(session.suggestions.first == "안녕하세요")
        #expect(session.nextSuggestion(client: field))
        #expect(field.text == "안녕하세요")
        #expect(session.nextSuggestion(client: field))
        #expect(field.text == session.suggestions[1])
        let second = session.suggestions[1]
        type(" ")
        #expect(field.text == second + " ")
        #expect(session.suggestions.isEmpty)
        #expect(!session.nextSuggestion(client: field))
    }

    @Test func escGoesBackToWhatWasTyped() {
        type("dkssudgk")
        _ = session.nextSuggestion(client: field)
        _ = session.handle(.escape, client: field)
        #expect(field.text == "안녕하")
        #expect(session.keys == "dkssudgk")
    }

    @Test func screenTextIsOfferedBeforeTheDictionary() {
        session.screenText = "$ git status\n변경 사항을 커밋하려면 add 하세요"
        type("qusrud")
        #expect(session.suggestions.first == "변경 사항을 커밋하려면 add 하세요")
    }

    @Test func textBeforeTheWordIsOffered() {
        field.insertText("배포는 금요일 오후에 합니다. ", replacing: nil)
        type("rmady")
        #expect(session.suggestions.first == "금요일 오후에 합니다.")
    }

    @Test func typedWordsAndSentencesAreCounted() {
        let history = TypedHistory(url: nil)
        session.history = history
        for _ in 0..<2 { type("rmadydlfdp qovh. ") }
        #expect(history.ranked().sentences == ["금요일에 배포."])
        #expect(history.ranked().words.contains("금요일에"))
    }
}

/// A word mixing Latin and Hangul on screen (G마켓) is offered by the keys that type it, while
/// the word is still shown as English.
@MainActor @Suite struct MixedWordCompletionTests {
    @Test func keysSpellAMixedWord() {
        #expect(DubeolsikLayout.keys(spelling: "G마켓") == "Gakzpt")
        #expect(DubeolsikLayout.keys(spelling: "닭값") == "ekfrrkqt")
        #expect(DubeolsikLayout.keys(spelling: "와") == "dhk")
    }

    @Test func offeredWhileShownAsEnglish() {
        let context = "지마켓 말고 G마켓 상세를 본다.\n"
        #expect(Completion.suggest("Gak", as: .english, context: context, keys: "Gak").first == "G마켓")
        #expect(Completion.suggest("Ga", as: .english, context: context, keys: "Ga").first == "G마켓")
    }

    @Test func typingItThroughTheSession() {
        let session = CapsLockTests.freshSession(), field = FakeTextField()
        field.text = "G마켓 수집량.\n"
        field.cursor = (field.text as NSString).length
        for ch in "Gak" { _ = session.handle(.letter(ch), client: field) }
        #expect(session.suggestions.first == "G마켓")
    }

    /// Picked once with Tab, the word is in the dictionary: its keys alone type it after that.
    @Test func pickedOnceItIsInTheDictionary() {
        let session = CapsLockTests.freshSession(), field = FakeTextField()
        session.history = TypedHistory(url: nil)
        field.text = "G마켓 수집량.\n"
        field.cursor = (field.text as NSString).length
        for ch in "Gak" { _ = session.handle(.letter(ch), client: field) }
        #expect(session.nextSuggestion(client: field))
        if !session.handle(.printable(" "), client: field) { field.insertText(" ", replacing: nil) }
        #expect(field.text.hasSuffix("G마켓 "))
        #expect(session.engine.dictionary.entries.contains { $0.keys == "Gakzpt" && $0.text == "G마켓" })

        let fresh = FakeTextField()
        for ch in "Gakzpt" { _ = session.handle(.letter(ch), client: fresh) }
        if !session.handle(.printable(" "), client: fresh) { fresh.insertText(" ", replacing: nil) }
        #expect(fresh.text == "G마켓 ")
    }
}
