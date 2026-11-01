import Foundation
import Testing
@testable import ArasoCore

/// Digits, `-` and `_` typed into an English or Korean word stay in it (`SplittingEngine.decideJoined`):
/// k8s, utf-8 and 안녕1 are one word, underlined to the end and switched whole, with a Korean particle
/// or word after them read as Korean (mp3를, React-기반).
@MainActor @Suite struct JoinedWordTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("araso-joined-\(UUID().uuidString).json")
        let engine = DictionaryEngine(base: SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter),
                                      english: trilingual.english, korean: trilingual.korean, japaneseParticles: true, storeURL: store)
        session = InputSession(engine: engine, converter: FakeConverter(), japaneseEnabled: true)
        field.insertsOverMarked = true
    }

    func type(_ s: String) {
        for ch in s {
            let handled = ch.isASCII && ch.isLetter ? session.handle(.letter(ch), client: field)
                                                    : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    @Test func digitsStayInTheWordBeingTyped() {
        type("k8s")
        #expect(field.text == "k8s")
        #expect(field.marked == NSRange(location: 0, length: 3)) // still underlined, not ㄴ after k8
        type(" ")
        #expect(field.text == "k8s ")
    }

    @Test func theSwitchKeyChangesTheWholeWord() {
        type("k8s ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "ㅏ8ㄴ ")
        type("utf-8")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "ㅏ8ㄴ ㅕㅅㄹ-8")
    }

    @Test func aKoreanParticleAfterTheDigitsSplits() {
        for (keys, text) in [("mp3fmf ", "mp3를 "), ("k8sdp ", "k8s에 "), ("utf-8dmf ", "utf-8을 "), ("gpt-4o ", "gpt-4o "),
                             ("h2o ", "h2o "), ("snake_case ", "snake_case "), ("merry-go ", "merry-go "),
                             ("mani-pedi ", "mani-pedi "), ("mp3fmf-1 ", "mp3fmf-1 ")] {
            field.text = ""; field.cursor = 0
            type(keys)
            #expect(field.text == text, "\(keys)")
        }
    }

    @Test func aKoreanWordKeepsItsDigits() {
        type("dkssud1")
        #expect(field.text == "안녕1")
        #expect(field.marked == NSRange(location: 0, length: 3)) // still the word being typed
        type(" ")
        #expect(field.text == "안녕1 ")
    }

    @Test func aWordShownAsKoreanSwitchesToEnglishWhole() {
        type("dkssud-1 ")
        #expect(field.text == "안녕-1 ")
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "dkssud-1 ")
    }

    @Test func aWordShownAsKoreanKeepsTheRestToo() {
        type("dbxm-8") // 유트-8, one word: the switch key takes it to dbxm-8 whole
        #expect(field.marked == NSRange(location: 0, length: 4))
        #expect(session.handle(.cycle, client: field))
        #expect(field.text == "dbxm-8")
    }

    /// A Korean front is only as sure as its letters alone (sork: 내가 at 0.87), so a Strict app's
    /// threshold applies to it as it does to the word without the digit.
    @Test func aKoreanFrontKeepsItsConfidence() {
        let engine = SplittingEngine(base: trilingual, english: trilingual.english, japanese: trilingual.segmenter)
        let joined = engine.decide("sork-1", context: DecisionContext())
        #expect(joined.language == .korean)
        #expect(joined.confidence == trilingual.decide("sork", context: DecisionContext()).confidence)
        #expect(joined.confidence < AppPolicy.strictThreshold)
        #expect(engine.decide("dkssud-1", context: DecisionContext()).confidence >= AppPolicy.strictThreshold)
    }

    @Test func piecesAfterTheMarkReadOnTheirOwn() {
        for (keys, text) in [("React-rlqks ", "React-기반 "), ("dkssud1gktpdy ", "안녕1하세요 "),
                             ("dkssud-hello ", "안녕-hello "), ("wp1ghl ", "제1회 ")] {
            field.text = ""; field.cursor = 0
            type(keys)
            #expect(field.text == text, "\(keys)")
        }
    }

    /// Code names and words before digits (#39): letters a Korean syllable could be stay as typed
    /// (cmd0, not 층0; en_s2c, not 두_s2c), and Korean words of two syllables or a number's word
    /// stay Korean (옵션1, 보고서_최종, 제1장, 주3회).
    @Test func codeNamesStayAsTyped() {
        for (keys, text) in [("cmd0 ", "cmd0 "), ("dir1 ", "dir1 "), ("en_s2c ", "en_s2c "), ("fn_x ", "fn_x "),
                             ("src_dir ", "src_dir "), ("app_cmd ", "app_cmd "), ("env_x ", "env_x "),
                             ("Dkssud-1 ", "Dkssud-1 "), ("React-1 ", "React-1 "), // an English-only capital
                             ("dhqtus1 ", "옵션1 "), ("qhrhtj_chlwhd ", "보고서_최종 "), ("ghldmlfhr_1023 ", "회의록_1023 "),
                             ("wp1wkd ", "제1장 "), ("wn3ghl ", "주3회 "), ("vy1 ", "표1 "), ("qhrhtj_wp1wkd ", "보고서_제1장 ")] {
            field.text = ""; field.cursor = 0
            type(keys)
            #expect(field.text == text, "\(keys)")
        }
    }

    @Test func aJapanesePhraseKeepsItsReading() {
        type("ra-men ")
        #expect(field.text.hasPrefix("らーめん"))
    }
}
