import Foundation
import Testing
@testable import SeamtypeCore

/// Deterministic converter: a few readings with fixed candidates, including a
/// first-clause candidate to exercise partial commits.
@MainActor final class FakeConverter: JapaneseConverter {
    var learned: [String] = []
    func candidates(for kana: String) -> [ConversionCandidate] {
        switch kana {
        case "きょうはいいてんきですね":
            return [.init(text: "今日はいい天気ですね", kanaCount: 12), .init(text: "今日は", kanaCount: 4),
                    .init(text: kana, kanaCount: 12)]
        case "いいてんきですね":
            return [.init(text: "いい天気ですね", kanaCount: 8), .init(text: kana, kanaCount: 8)]
        case "へんかん":
            return [.init(text: "変換", kanaCount: 4), .init(text: "返還", kanaCount: 4), .init(text: "編纂", kanaCount: 4)]
        case "３がつ":
            return [.init(text: "三月", kanaCount: 3), .init(text: "３月", kanaCount: 3), .init(text: "3月", kanaCount: 3)]
        case "3じ":
            return [.init(text: "三時", kanaCount: 2), .init(text: "３時", kanaCount: 2), .init(text: "3時", kanaCount: 2),
                    .init(text: "3", kanaCount: 1)]
        case "１２３":
            return [.init(text: "一二三", kanaCount: 3), .init(text: "123", kanaCount: 3), .init(text: kana, kanaCount: 3)]
        default:
            return [.init(text: kana, kanaCount: kana.count)]
        }
    }
    func learn(_ candidate: ConversionCandidate, for kana: String) { learned.append(candidate.text) }
    func save() {}
}

@MainActor @Suite struct JapaneseSessionTests {
    let field = FakeTextField()
    let converter = FakeConverter()
    let session: InputSession

    init() {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-ja-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        session = InputSession(engine: engine, converter: converter, japaneseEnabled: true)
    }

    func type(_ s: String) {
        // Keys the input method passes on are typed by the app, as in a real text field.
        for ch in s {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    @Test func previewShowsKanaWhileTyping() {
        type("kyouhaiitenk")
        #expect(field.text == "きょうはいいてんk")
    }

    /// Return commits what was shown: letters waiting for their vowel stay letters rather than
    /// splitting an English word out of the phrase (わたしhag), and only n becomes ん.
    @Test func returnCommitsPendingLettersAsShown() {
        for (keys, shown, committed) in [("watashihag", "わたしはg", "わたしはg"), ("kyouhaiitenkides", "きょうはいいてんきでs", "きょうはいいてんきでs"),
                                         ("nagaremasen", "ながれませn", "ながれません")] {
            type(keys)
            #expect(field.text.hasSuffix(shown), "\(keys): \(field.text)")
            #expect(session.handle(.enter, client: field))
            #expect(field.text.hasSuffix(committed), "\(keys): \(field.text)")
            type(" ")
        }
    }

    @Test func spaceConvertsAndReturnCommits() {
        type("kyouhaiitenkidesune ")
        #expect(session.conversion != nil)
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.handle(.enter, client: field))
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.conversion == nil)
        #expect(converter.learned == ["今日はいい天気ですね"])
    }

    /// A short word shown as kana converts on Space, though once it ends it reads as English
    /// (zio showed じお, then went in as "zio"); an English word still goes in as typed.
    @Test func spaceConvertsAShortWordShownAsKana() {
        type("zio")
        #expect(field.text == "じお")
        type(" ")
        #expect(session.conversion != nil)
        #expect(session.handle(.enter, client: field))
        type("taco ")
        #expect(field.text == "じおtaco ")
    }

    @Test func spaceCyclesCandidatesAndNumbersPick() {
        type("henkan ")
        #expect(field.text == "変換")
        type(" ")
        #expect(field.text == "返還")
        session.handle(.up, client: field)
        #expect(field.text == "変換")
        type("3")
        #expect(field.text == "編纂")
        #expect(session.conversion == nil)
    }

    @Test func firstClauseCandidateKeepsConvertingTheRest() {
        type("kyouhaiitenkidesune ")
        session.handle(.down, client: field) // 今日は (covers 4 kana)
        #expect(field.text == "今日はいいてんきですね")
        session.handle(.enter, client: field)
        #expect(field.text == "今日はいい天気ですね")
        #expect(session.conversion?.kana == "いいてんきですね")
        session.handle(.enter, client: field)
        #expect(session.conversion == nil)
        #expect(field.text == "今日はいい天気ですね")
    }

    @Test func escapeReturnsToKana() {
        type("henkan ")
        session.handle(.escape, client: field)
        #expect(session.conversion == nil)
        #expect(field.text == "へんかん")
        session.handle(.delete, client: field)
        #expect(field.text == "へんか")
    }

    @Test func deleteTakesOffAWholeKana() {
        type("kannkoku")
        #expect(field.text == "かんこく")
        session.handle(.delete, client: field)
        #expect(field.text == "かんこ")
        session.handle(.delete, client: field)
        #expect(field.text == "かん")
        type("ji ")
        #expect(converter.learned.isEmpty)
        #expect(session.conversion?.kana == "かんじ")
    }

    @Test func deleteKeepsAPendingLetterSeparate() {
        type("kannkok")
        #expect(field.text == "かんこk")
        session.handle(.delete, client: field)
        #expect(field.text == "かんこ")
    }

    @Test func deleteSplitsContractedAndDoubledKana() {
        type("kyouha")
        session.handle(.delete, client: field)
        session.handle(.delete, client: field)
        #expect(field.text == "きょ")
        session.handle(.delete, client: field)
        #expect(field.text == "き")
        type("tte")
        #expect(field.text == "きって")
        session.handle(.delete, client: field)
        #expect(field.text == "きっ")
        type("ta")
        #expect(field.text == "きった")
    }

    @Test func returnWithoutConvertingCommitsKanaOnly() {
        type("arigatou")
        #expect(field.text == "ありがとう")
        let consumed = session.handle(.enter, client: field)
        #expect(consumed) // a Japanese IME's Return only confirms the text
        #expect(field.text == "ありがとう")
    }

    @Test func previewMatchesWhatGetsCommitted() {
        // "kanji" is an English dictionary word: outside Japanese text it stays English,
        // and the preview says so before Return.
        type("kanji")
        #expect(field.text == "kanji")
        let consumed = session.handle(.enter, client: field)
        #expect(consumed) // Return only confirms, whatever the language
        #expect(field.text == "kanji")
        #expect(field.marked.location == NSNotFound)
    }

    @Test func punctuationStaysInsideJapanesePhrase() {
        type("arigatou.")
        #expect(field.text == "ありがとう。")
        type("ra-men")
        #expect(field.text == "ありがとう。らーめn") // ん waits for the next key, like any Japanese IME
    }

    /// After Japanese a symbol is full-width and underlined, as in a Japanese IME: Return only
    /// confirms it, the next letter starts a word of its own.
    @Test func symbolAfterJapaneseWaitsForReturn() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("!?")
        #expect(field.text == "変換！？")
        #expect(field.marked.location != NSNotFound)
        #expect(session.handle(.enter, client: field))
        #expect(field.text == "変換！？")
        #expect(field.marked.location == NSNotFound)
        type("_")
        session.handle(.delete, client: field)
        #expect(field.text == "変換！？")
        type("/wo")
        #expect(field.text == "変換！？・を")
    }

    @Test func symbolAfterJapaneseConvertsWithSpace() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("_ ")
        #expect(session.conversion?.kana == "＿")
    }

    @Test func numbersAfterJapaneseStayHalfWidth() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("3.5:")
        #expect(field.text == "変換3.5:")
    }

    @Test func bracketsCloseTheWayTheyOpened() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("(hello)")
        session.handle(.enter, client: field)
        #expect(field.text == "変換（hello）")
    }

    @Test func symbolsJoinOnlyAFinishedJapaneseWord() {
        type("nihon.")
        #expect(field.text == "にほん。")
    }

    @Test func symbolsInEnglishStayHalfWidth() {
        type("foo_bar (baz) a/b ")
        #expect(field.text == "foo_bar (baz) a/b ")
    }

    /// Off by default: digits after Japanese stay half-width and go to the app.
    @Test func digitsStayHalfWidthByDefault() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("123")
        #expect(field.text == "変換123")
    }

    @Test func fullWidthDigitsAfterJapanese() {
        session.fullWidthDigits = true
        type("henkan ")
        session.handle(.enter, client: field)
        type("123")
        #expect(field.text == "変換１２３")
        #expect(field.marked.location != NSNotFound)
        type(" ")
        #expect(session.conversion?.candidates.prefix(3).map(\.text) == ["１２３", "123", "一二三"])
        type(" ")
        session.handle(.enter, client: field)
        #expect(field.text == "変換123")
    }

    /// Addresses and phone numbers: the punctuation inside a number is full-width too, and Delete
    /// takes it off one character at a time.
    @Test func fullWidthNumberPunctuation() {
        session.fullWidthDigits = true
        type("henkan ")
        session.handle(.enter, client: field)
        type("03-1234")
        #expect(field.text == "変換０３－１２３４")
        session.handle(.delete, client: field)
        session.handle(.delete, client: field)
        #expect(field.text == "変換０３－１２")
    }

    /// Inside a phrase a number joins it, and candidates that keep the digits come first.
    @Test func numberInsideAPhrase() {
        session.fullWidthDigits = true
        type("henkan ")
        session.handle(.enter, client: field)
        type("3gatsu ")
        #expect(session.conversion?.candidates.prefix(3).map(\.text) == ["３月", "3月", "三月"])
    }

    @Test func digitsAfterEnglishStayHalfWidth() {
        session.fullWidthDigits = true
        type("hello 123 ")
        #expect(field.text == "hello 123 ")
    }

    /// A switch key right after digits the app typed makes them a Japanese number, as if typed
    /// after Japanese with full-width digits on.
    @Test func switchKeyAfterDigitsMakesThemFullWidth() {
        type("hello 123")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "hello １２３")
        #expect(field.marked.location != NSNotFound)
        type(" ")
        #expect(session.conversion?.candidates.prefix(2).map(\.text) == ["１２３", "123"])
        session.handle(.enter, client: field)
        #expect(field.text == "hello １２３")
    }

    /// The same for symbols: [ at the start of a line opens a Japanese quote, and ] closes it.
    @Test func switchKeyAfterSymbolMakesItJapanese() {
        type("[")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "「")
        type("henkan]")
        #expect(field.text == "「へんかん」")
    }

    /// One digit: it becomes １, neither doubled (1１) nor lost.
    @Test func switchKeyAfterOneDigit() {
        type("hello 1")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "hello １")
        session.handle(.enter, client: field)
        #expect(field.text == "hello １")
    }

    /// An app that can't read back its text (most terminals): the digits stay as typed.
    @Test func switchKeyAfterDigitsWhereTheAppCantBeRead() {
        field.readable = false
        type("hello 1")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "hello 1")
        #expect(session.keys.isEmpty)
    }

    /// The same app with a counter: the phrase converts on its own (no 33時).
    @Test func counterWhereTheAppCantBeRead() {
        field.readable = false
        type("henkan ")
        session.handle(.enter, client: field)
        type("3ji ")
        #expect(field.text == "変換3じ")
        session.handle(.enter, client: field)
        #expect(field.text == "変換3じ")
    }

    /// Nothing typed by the app just before: the switch key stays a no-op (and after a space too).
    @Test func switchKeyAfterSpaceDoesNothing() {
        type("123 ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "123 ")
    }

    /// In Japanese text, a counter typed right after a number converts with it: 3ji is 3時, as
    /// typed, first (ji alone reads as English).
    @Test func numberBeforePhraseJoinsConversion() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("3ji ")
        #expect(session.conversion?.candidates.first?.text == "3時")
        #expect(field.text == "変換3時")
        session.handle(.enter, client: field)
        #expect(field.text == "変換3時")
    }

    /// Back to kana from such a conversion puts the number back as typed.
    @Test func numberBeforePhraseBackToKana() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("3ji ")
        session.handle(.cycle, client: field)
        #expect(field.text == "変換3じ")
        #expect(session.keys == "ji")
    }

    /// Units after a number stay English in Japanese text, and nothing changes elsewhere.
    @Test func numberBeforeOtherWordsUnchanged() {
        type("henkan ")
        session.handle(.enter, client: field)
        type("5km ")
        #expect(field.text == "変換5km ")
        let other = FakeTextField()
        for ch in "3pm 3dlf 1on1 " where !(ch.isLetter ? session.handle(.letter(ch), client: other) : session.handle(.printable(ch), client: other)) {
            other.insertText(String(ch), replacing: nil)
        }
        #expect(other.text == "3pm 3일 1on1 ")
    }

    @Test func fullWidthSpaceAfterJapanese() {
        type("henkan ")
        session.handle(.enter, client: field)
        #expect(session.handle(.shiftSpace, client: field)) // ⇧Space: the other width
        #expect(field.text == "変換　")
        session.fullWidthSpace = true
        type(" ")
        #expect(field.text == "変換　　")
        #expect(!session.handle(.shiftSpace, client: field)) // the app types the half-width one
    }

    @Test func noFullWidthWhereTheAppSaysNo() {
        let policies = AppPolicies(overrides: ["test.terminal": .init(fullWidth: false)])
        let terminal = InputSession(engine: session.engine, policies: policies, converter: converter, japaneseEnabled: true)
        terminal.activate(app: "test.terminal")
        terminal.fullWidthDigits = true
        terminal.fullWidthSpace = true
        let field = FakeTextField()
        for ch in "henkan " where !(ch.isLetter ? terminal.handle(.letter(ch), client: field) : terminal.handle(.printable(ch), client: field)) {
            field.insertText(String(ch), replacing: nil)
        }
        terminal.handle(.enter, client: field)
        for ch in "12 " where !terminal.handle(.printable(ch), client: field) { field.insertText(String(ch), replacing: nil) }
        #expect(field.text == "変換12 ")
    }

    @Test func numberHelpers() {
        #expect(InputSession.digits(of: "東京都１－２") == "12")
        #expect(InputSession.halfWidth("０３－１２３４") == "03-1234")
        #expect(RomajiComposer.compose("03-1234").text == "０３－１２３４")
        #expect(RomajiComposer.compose("ra-men").text == "らーめん")
    }

    @Test func typingOnAfterConversionCommitsIt() {
        type("henkan ")
        type("wo")
        #expect(field.text == "変換を")
        #expect(session.conversion == nil)
    }

    @Test func englishAndKoreanStillWork() {
        type("hello dkssud ")
        #expect(field.text == "hello 안녕 ")
    }

    @Test func keysRemainderAfterKana() {
        #expect(InputSession.keys("kyouhaiitenki", after: 4) == "iitenki")
        #expect(InputSession.keys("kitte", after: 2) == "te")
        #expect(InputSession.keys("konnichiha", after: 2) == "nichiha")
    }
}

/// nn is ㅜㅜ in Korean chat and ん in Japanese: the preview shows what Space commits (it showed
/// ん and went in as ㅜㅜ), the sentence decides which, and the switch key reaches both.
@MainActor @Suite struct ChatJamoTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-cj-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        session = InputSession(engine: engine, policies: .escSwitches, japaneseEnabled: true)
    }

    func type(_ s: String) {
        for ch in s {
            switch ch {
            case "⎋": _ = session.handle(.escape, client: field)
            case let c where c.isLetter: _ = session.handle(.letter(c), client: field)
            default: if !session.handle(.printable(ch), client: field) { field.insertText(String(ch), replacing: nil) }
            }
        }
    }

    @Test func showsWhatSpaceCommits() {
        type("nn")
        #expect(field.text == "ㅜㅜ")
        type(" ")
        #expect(field.text == "ㅜㅜ ")
        type("sugoi nn")
        #expect(field.text.hasSuffix("すごい ん"))
        type(" ")
        #expect(field.text.hasSuffix("すごい ん "))
    }

    /// A doubled consonant with nothing after its っ isn't Japanese on its way: ff showed っf
    /// and went in as ff, ss showed っs and went in as っs. って (tte) is still Japanese.
    @Test(arguments: [("ff", "ff"), ("ww", "ww"), ("ss", "ss"), ("xxx", "xxx"), ("zz", "ㅋㅋ"), ("ttedokoni", "ってどこに")])
    func doubledConsonantShowsWhatItCommits(keys: String, word: String) {
        type(keys)
        #expect(field.text == word)
        type(" ")
        #expect(field.text == word + " ")
    }

    @Test func switchKeyReachesTheChatReading() {
        type("nn⎋⎋⎋")
        #expect(field.text == "ㅜㅜ")
        type(" ⎋")
        #expect(field.text == "ん ")
        type("⎋⎋")
        #expect(field.text == "ㅜㅜ ")
    }
}

/// A word learned as Japanese types as Japanese only while Japanese is on.
@MainActor @Suite struct LearnedJapaneseTests {
    @Test(arguments: [(true, "すし "), (false, "sushi ")])
    func followsTheJapaneseSetting(japanese: Bool, typed: String) {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-lj-\(UUID().uuidString).json")
        let engine = LearningEngine(base: japanese ? SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter)
                                                   : splitting, storeURL: lex)
        engine.learn("sushi", as: .japanese, engineChoice: .english)
        engine.learn("sushi", as: .japanese, engineChoice: .english)
        let session = InputSession(engine: engine, japaneseEnabled: japanese)
        let field = FakeTextField()
        for ch in "sushi " {
            if !(ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)) {
                field.insertText(String(ch), replacing: nil)
            }
        }
        #expect(field.text == typed)
    }
}

/// A Strict app with Japanese on: a consonant at the end, still waiting for its vowel while
/// typed, kept a Korean word under the threshold on screen, and Space then committed it as
/// Korean (qud showed qud and went in as 병).
@MainActor @Suite struct StrictJapaneseTests {
    @Test(arguments: [("qud", "병"), ("eho", "돼"), ("ajanf", "머물")])
    func koreanWordShowsWhatItCommits(keys: String, word: String) {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-sj-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        let session = InputSession(engine: engine, policies: AppPolicies(overrides: [AppPolicies.defaultKey: .init(conversionThreshold: AppPolicy.strictThreshold)]),
                                   converter: FakeConverter(), japaneseEnabled: true)
        let field = FakeTextField()
        for ch in keys { _ = session.handle(.letter(ch), client: field) }
        #expect(field.text == word)
        #expect(session.handle(.enter, client: field))
        #expect(field.text == word)
    }

    /// A short token the threshold keeps English still converts when its kana are on screen.
    @Test func spaceConvertsAShortTokenShownAsKana() {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-sj-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        let session = InputSession(engine: engine, policies: AppPolicies(overrides: [AppPolicies.defaultKey: .init(conversionThreshold: AppPolicy.strictThreshold)]),
                                   converter: FakeConverter(), japaneseEnabled: true)
        let field = FakeTextField()
        for ch in "ka" { _ = session.handle(.letter(ch), client: field) }
        #expect(field.text == "か")
        #expect(session.handle(.printable(" "), client: field))
        #expect(session.conversion != nil)
    }
}

@MainActor @Suite struct TextReplacementTests {
    let field = FakeTextField()
    let converter = FakeConverter()
    let session: InputSession

    init() {
        let lex = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-tr-\(UUID().uuidString).json")
        let engine = LearningEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter), storeURL: lex)
        session = InputSession(engine: engine, policies: AppPolicies(overrides: [AppPolicies.defaultKey: .init(conversionThreshold: AppPolicy.strictThreshold)]),
                               converter: converter, japaneseEnabled: true)
        session.replacements = ["ㅈㅅ": ["죄송합니다"], "주소": ["서울시"], "よろ": ["よろしくお願いします"], "go": ["gone"]]
    }

    func type(_ s: String) {
        for ch in s {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    /// The shortcut goes in as typed, even in a Strict app, so the app can replace it on Space.
    @Test func koreanShortcutWinsTheDecision() {
        type("wt wnth ")
        #expect(field.text == "ㅈㅅ 주소 ")
    }

    @Test func japaneseShortcutIsTheFirstCandidate() {
        type("yoro ")
        #expect(session.conversion?.candidates.first?.text == "よろしくお願いします")
        session.handle(.enter, client: field)
        #expect(field.text == "よろしくお願いします")
    }

    /// gu reads as 혀, but gu- is on its way to the shortcut ぐー.
    @Test func japaneseShortcutWithASymbol() {
        session.replacements["ぐー"] = ["グーグル"]
        type("gu- ")
        #expect(session.conversion?.candidates.first?.text == "グーグル")
    }

    /// A shortcut entered more than once offers every phrase, in order, before the converter's own.
    @Test func everyPhraseOfAShortcutIsACandidate() {
        session.replacements["よろ"] = ["よろしくお願いします", "よろしく", "夜露死苦"]
        type("yoro ")
        #expect(session.conversion?.candidates.prefix(3).map(\.text) == ["よろしくお願いします", "よろしく", "夜露死苦"])
        #expect(session.conversion?.candidates.filter { $0.text == "よろしく" }.count == 1)
    }

    /// Live conversion shows conversions only, never a completion of what was typed.
    @Test func liveConversionSkipsCompletions() {
        let live = InputSession(engine: session.engine, converter: PredictingConverter(), japaneseEnabled: true, liveConversion: true)
        let field = FakeTextField()
        for ch in "arigatou" where !live.handle(.letter(ch), client: field) { field.insertText(String(ch), replacing: nil) }
        #expect(field.text == "ありがとう")
    }

    @Test func englishShortcutsAreLeftToTheEngine() {
        type("kyouha go")
        #expect(session.lastTrace?.decision.explanation != "text replacement shortcut")
    }
}

/// A converter whose first candidate for ゆーちゅ is a completion.
@MainActor final class PredictingConverter: JapaneseConverter {
    func candidates(for kana: String) -> [ConversionCandidate] {
        [.init(text: "YouTube", kanaCount: kana.count, isPrediction: true), .init(text: kana, kanaCount: kana.count)]
    }
    func learn(_ candidate: ConversionCandidate, for kana: String) {}
    func save() {}
}
