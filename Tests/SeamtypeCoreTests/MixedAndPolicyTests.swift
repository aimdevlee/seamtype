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
    ])
    func splitsEnglishPlusParticle(keys: String, expected: String) {
        let d = splitting.decide(keys, context: DecisionContext())
        #expect(d.language == .mixed, "\(d.explanation)")
        #expect(d.output == expected)
    }

    // A whole Korean word straight after an English one, no space.
    @Test(arguments: [
        ("hellodnjfem", "hello월드"), ("githubtjqj", "github서버"), ("loginghkaus", "login화면"),
        ("designvhsxm", "design폰트"), ("Reactzjavhsjsxm", "React컴포넌트"), ("VSCodetjfwjd", "VSCode설정"),
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
