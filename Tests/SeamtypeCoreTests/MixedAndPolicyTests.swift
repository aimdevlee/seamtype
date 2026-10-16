import Foundation
import Testing
@testable import SeamtypeCore

let splitting = SplittingEngine(base: sharedEngine, english: sharedEngine.english)

@Suite struct MixedWordTests {
    @Test(arguments: [
        ("githubdp", "github에"), ("APIfmf", "API를"), ("commitgotj", "commit해서"),
        ("serverdptj", "server에서"), ("pythondmfh", "python으로"), ("deploygoTdj", "deploy했어"),
        // Names typed with their capitals, in the word list or not.
        ("TextEditdptj", "TextEdit에서"), ("Slackdptj", "Slack에서"), ("VSCodedptj", "VSCode에서"),
        ("GitHubdp", "GitHub에"), ("iPhonedptj", "iPhone에서"),
        // Acronyms starting on a Korean shift key, typed in capitals throughout.
        ("TVdp", "TV에"), ("QAfmf", "QA를"), ("RNdms", "RN은"),
    ])
    func splitsEnglishPlusParticle(keys: String, expected: String) {
        let d = splitting.decide(keys, context: DecisionContext())
        #expect(d.language == .mixed, "\(d.explanation)")
        #expect(d.output == expected)
    }

    // A lingering Shift (ㄲ then ㅜ as N) doesn't make the front a name: no split.
    @Test(arguments: [("RNfdmf", "꿀을"), ("qkRNleh", "바뀌도"), ("djEJsrj", "어떤거"), ("TMfkrh", "쓰라고")])
    func lingeringShiftIsNotAName(keys: String, expected: String) {
        let d = splitting.decide(keys, context: DecisionContext())
        #expect(d.language == .korean, "\(keys) → \(d.output) \(d.explanation)")
        #expect(d.output == expected)
    }

    // Fast-typed Korean whose first two keys spell an acronym stays Korean: it reads as Korean
    // throughout (따라서 as EKfktj); its first syllable is rare but has been seen (삐졌어 as QLwuTdj,
    // 쭈그리고 as WNrmflrh, from the word lists); or no known Korean word follows (뾰족한 as QYwhrgks).
    // The word after may hold a rare syllable (또공룡이 as EHrhdfyddl): only the front is judged.
    // 쓰정책 and 씨서버 are what TMwjdcor and TLtjqj give: the acronym + Korean word shape that can't
    // be told from Korean.
    @Test(arguments: [("EKfktj", "따라서"), ("RJsoek", "꺼내다"), ("WHroek", "쪼개다"), ("TMfprl", "쓰레기"),
                      ("RUdksrh", "껴안고"), ("ELehdrkq", "띠동갑"), ("QYwhrgks", "뾰족한"), ("QLdpfh", "삐에로"),
                      ("QLwuTdj", "삐졌어"), ("WUajrek", "쪄먹다"), ("WUqjfuTdj", "쪄버렸어"), ("WlffjTdj", "찔렀어"),
                      ("WNrmflrh", "쭈그리고"), ("EHrhdfyddl", "또공룡이"),
                      ("TMwjdcor", "쓰정책"), ("TLtjqj", "씨서버")])
    func acronymShapedKoreanStaysKorean(keys: String, expected: String) {
        let d = splitting.decide(keys, context: DecisionContext())
        #expect(d.language == .korean, "\(keys) → \(d.output) \(d.explanation)")
        #expect(d.output == expected)
    }

    // A whole Korean word straight after an English one, no space.
    @Test(arguments: [
        ("hellodnjfem", "hello월드"), ("githubtjqj", "github서버"), ("loginghkaus", "login화면"),
        ("designvhsxm", "design폰트"), ("Reactzjavhsjsxm", "React컴포넌트"), ("VSCodetjfwjd", "VSCode설정"),
        // An acronym or name starting on a Korean shift key (P, W, O) is still English: the Korean
        // word's lowercase after it is no lingering Shift.
        ("PDFvkdlf", "PDF파일"), ("WWDCvhfja", "WWDC포럼"), ("OAuthdlswmd", "OAuth인증"),
        // ㅒ/ㅖ after a capital (RPA, TPS): the key before was typed with Shift too, so not a syllable.
        ("RPAdlswmd", "RPA인증"), ("TPSvkdlf", "TPS파일"),
        // An acronym whose capitals a lingering Shift could explain (EU as ㄸ+ㅕ) still splits when
        // the whole token doesn't read as Korean (뗘, 쎠, 쓔 are syllables nobody types) and a known
        // Korean word follows.
        ("EUwjdcor", "EU정책"), ("TUtjqj", "TU서버"), ("TBvkdlf", "TB파일"), ("ETLwjdcor", "ETL정책"), ("TTLtjfwjd", "TTL설정"),
    ])
    func splitsEnglishPlusKoreanWord(keys: String, expected: String) {
        let d = splitting.decide(keys, context: DecisionContext())
        #expect(d.language == .mixed, "\(d.explanation)")
        #expect(d.output == expected)
    }

    // Korean typed with shift (쌍꺼풀은, 있어, 끝에서, 쐈어요) isn't a capitalized name;
    // names that spell like English (cartman ≠ car스무) and clean romaji (はさんそを) stay whole.
    @Test(arguments: ["work", "park", "hello", "thanks", "dkssudgktpdy", "akadp", "ruxdp", "wkfrk",
                      "TkdRjvnfdms", "dlTdj", "Rmxdptj", "ThkTdjdy", "RoRmtgkgfusk",
                      "cartman", "Cartman", "stuntman", "comstock", "wolfsbane", "hasansowo", "nonakawo"])
    func leavesWholeWordsAlone(keys: String) {
        #expect(splitting.decide(keys, context: DecisionContext()).language != .mixed)
    }

    @Test func escCyclesThroughReadings() {
        #expect(Language.english.next(for: "githubdp") == .mixed)
        #expect(Language.mixed.next(for: "githubdp") == .english) // 햐소ㅕㅠ에 is garbled: skipped
        #expect(Language.korean.next(for: "githubdp") == .english)
        #expect(Language.english.next(for: "dkssud") == .korean)
        // No split available: english ↔ korean.
        #expect(Language.english.next(for: "hello") == .korean)
    }

    @Test func mixedSentence() {
        let converter = TextConverter(engine: splitting)
        #expect(converter.convert("dlrjs githubdp commitgkf rjdi").output == "이건 github에 commit할 거야")
    }
}

@Suite struct AppPolicyTests {
    /// No app is special unless the user lists it.
    @Test func everyAppStartsAtTheDefault() {
        let policies = AppPolicies()
        #expect(policies.policy(for: "com.apple.Terminal") == .standard)
        #expect(policies.policy(for: "com.kakao.KakaoTalkMac") == .standard)
        #expect(policies.policy(for: nil) == .standard)
        #expect(policies.apps.isEmpty)
    }

    @Test func userEntriesAndPrefixes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"com.apple.Terminal": {"enabled": false}, "com.jetbrains.": {"conversionThreshold": 0.97}}"#.utf8).write(to: url)
        let policies = AppPolicies.load(from: url)
        #expect(policies.policy(for: "com.apple.Terminal").enabled == false)
        #expect(policies.policy(for: "com.jetbrains.intellij").conversionThreshold == 0.97)
        #expect(AppPolicies.load(from: url.appendingPathExtension("missing")).overrides.isEmpty)
    }

    /// An app's entry changes only the keys it names; the rest follows the user's default.
    @Test func appEntriesSitOnTheDefault() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"*": {"switchKeys": ["escape"]}, "com.mitchellh.ghostty": {"conversionThreshold": 0.97}, "com.example.Game": {"enabled": false}}"#.utf8).write(to: url)
        let policies = AppPolicies.load(from: url)
        #expect(policies.defaultPolicy == AppPolicy(switchKeys: [.escape]))
        #expect(policies.policy(for: "com.mitchellh.ghostty") == AppPolicy(conversionThreshold: 0.97, switchKeys: [.escape]))
        #expect(policies.policy(for: "com.example.Game") == AppPolicy(enabled: false, switchKeys: [.escape]))
        #expect(policies.policy(for: "com.apple.Terminal") == AppPolicy(switchKeys: [.escape]))
        #expect(policies.apps == ["com.example.Game", "com.mitchellh.ghostty"])
    }

    /// Holding the word after Space is an app's own choice, and only that key is written for it.
    @Test func holdSpaceIsPerApp() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-apps-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"com.mitchellh.ghostty": {"holdSpace": true}}"#.utf8).write(to: url)
        var policies = AppPolicies.load(from: url)
        #expect(policies.policy(for: "com.mitchellh.ghostty") == AppPolicy(holdSpace: true))
        #expect(policies.policy(for: "com.apple.TextEdit") == .standard)
        policies.set(AppPolicy(holdSpace: true), for: "com.apple.Terminal")
        #expect(policies.overrides["com.apple.Terminal"] == AppPolicy.Override(holdSpace: true))
        // Written and read back (Override's Codable names each key).
        try policies.save(to: url)
        #expect(AppPolicies.load(from: url).policy(for: "com.apple.Terminal") == AppPolicy(holdSpace: true))
    }
}

@MainActor @Suite struct SessionPolicyTests {
    let field = FakeTextField()
    let learning: LearningEngine
    let session: InputSession

    init() {
        let dir = FileManager.default.temporaryDirectory
        learning = LearningEngine(base: splitting, storeURL: dir.appendingPathComponent("seamtype-lex-\(UUID().uuidString).json"))
        let policies = AppPolicies(overrides: ["*": .init(switchKeys: [.escape, .shiftEscape]),
                                               "test.strict": .init(conversionThreshold: 0.9999),
                                               "test.off": .init(enabled: false)])
        session = InputSession(engine: learning, policies: policies)
    }

    func type(_ s: String) {
        // Keys the input method passes on are typed by the app, as in a real text field.
        for ch in s {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled { field.insertText(String(ch), replacing: nil) }
        }
    }

    @Test func strictAppKeepsUncertainWordsEnglish() {
        session.activate(app: "test.strict")
        type("dhsmf ")
        #expect(field.text == "dhsmf ")
    }

    @Test func disabledAppPassesKeysThrough() {
        session.activate(app: "test.off")
        #expect(!session.handle(.letter("d"), client: field))
        #expect(field.text.isEmpty)
    }

    @Test func escCyclesMixedWordAfterCommit() {
        type("githubdp ")
        #expect(field.text == "github에 ")
        // The garbled Korean reading (햐소ㅕㅠ에) is skipped: github에 ↔ githubdp.
        session.handle(.escape, client: field)
        #expect(field.text == "githubdp ")
        session.handle(.escape, client: field)
        #expect(field.text == "github에 ")
    }

    @Test func correctionCountsOnceWithTheFinalChoice() {
        session.activate(app: "com.example.chat")
        type("hello ")
        session.handle(.escape, client: field)   // hello → ㅗ디ㅣㅐ
        #expect(learning.pending.isEmpty)         // window still open
        type("x")                                 // any other key closes it
        #expect(learning.pending == ["hello": .korean])
    }

    @Test func nothingCountsWhenTheWordIsFlippedBack() {
        type("hello ")
        session.handle(.escape, client: field)
        session.handle(.escape, client: field)
        type("x")
        #expect(learning.pending.isEmpty)
    }
}
