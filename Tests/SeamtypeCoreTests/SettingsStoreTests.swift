import Foundation
import Testing
@testable import SeamtypeCore

/// What the input menu and the settings window write: settings.json, apps.json, lexicon.json.
@Suite struct SettingsStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-store-\(UUID().uuidString)")

    /// A fixed engine, so tests control what "the engine's own choice" is.
    struct Fixed: DecisionEngine {
        let language: Language
        func decide(_ keys: String, context: DecisionContext) -> Decision {
            Decision(language: language, confidence: 0.9, output: keys, explanation: "")
        }
    }

    @Test func rightCommandPauseIsOnUnlessTurnedOff() throws {
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{ "japanese": true }"#.utf8).write(to: url)
        #expect(Settings.load(from: url).rightCommandPause)
        try Settings(rightCommandPause: false).save(to: url)
        #expect(!Settings.load(from: url).rightCommandPause)
        #expect(Settings.load(from: url).returnConfirmsOnly)
        try Settings(returnConfirmsOnly: false).save(to: url)
        #expect(!Settings.load(from: url).returnConfirmsOnly)
    }

    @Test func switchKeyIsRightOptionUnlessChosen() throws {
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{ "japanese": true }"#.utf8).write(to: url)
        #expect(Settings.load(from: url).switchKey == .rightOption)
        try Settings(switchKey: .optionSpace).save(to: url)
        #expect(Settings.load(from: url).switchKey == .optionSpace)
        try Data(#"{ "switchKey": "capsLock" }"#.utf8).write(to: url) // unknown: the default
        #expect(Settings.load(from: url).switchKey == .rightOption)
    }

    @Test func settingsSaveKeepsUnknownKeys() throws {
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{ "japanese": false, "future": 3 }"#.utf8).write(to: url)
        try Settings(japanese: true, liveConversion: true).save(to: url)
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(object["future"] as? Int == 3)
        #expect(Settings.load(from: url) == Settings(japanese: true, liveConversion: true))
    }

    @Test func appEntryNamesOnlyWhatDiffersFromTheDefault() throws {
        var policies = AppPolicies()
        policies.setDefault(AppPolicy(escapeToApp: true))
        #expect(policies.overrides["*"] == AppPolicy.Override(escapeToApp: true))

        var ghostty = policies.policy(for: "com.mitchellh.ghostty")
        ghostty.conversionThreshold = AppPolicy.strictThreshold
        policies.set(ghostty, for: "com.mitchellh.ghostty")
        #expect(policies.overrides["com.mitchellh.ghostty"] == AppPolicy.Override(conversionThreshold: 0.97))

        // Set back to the default's values, the app stays listed (the user added it).
        policies.set(policies.defaultPolicy, for: "com.mitchellh.ghostty")
        #expect(policies.overrides["com.mitchellh.ghostty"] == AppPolicy.Override())
        #expect(policies.apps == ["com.mitchellh.ghostty"])

        // A default back at Seamtype's own leaves no "*" entry.
        policies.setDefault(.standard)
        #expect(policies.overrides["*"] == nil)

        var game = policies.policy(for: "com.example.Game")
        game.enabled = false
        policies.set(game, for: "com.example.Game")
        let url = dir.appendingPathComponent("apps.json")
        try policies.save(to: url)
        #expect(AppPolicies.load(from: url).policy(for: "com.example.Game").enabled == false)
        #expect(AppPolicies.load(from: url).apps == ["com.example.Game", "com.mitchellh.ghostty"])
    }

    @Test func forgetAndUndoLearnedWords() {
        let url = dir.appendingPathComponent("lexicon.json")
        let learning = LearningEngine(base: Fixed(language: .english), storeURL: url)
        learning.learn("dlrjs", as: .korean)
        #expect(learning.pending == ["dlrjs": .korean])
        #expect(learning.lastLearned == nil)
        learning.learn("dlrjs", as: .korean)
        #expect(learning.learned == ["dlrjs": .korean])
        #expect(learning.lastLearned == "dlrjs")

        learning.forget("dlrjs")
        #expect(learning.learned.isEmpty && learning.pending.isEmpty)
        #expect(learning.lastLearned == nil)

        learning.learn("gks", as: .korean)
        learning.learn("rk", as: .korean)
        learning.learn("rk", as: .korean)
        // Another process (the settings window) edits the file; reload picks it up.
        let other = LearningEngine(base: Fixed(language: .english), storeURL: url)
        other.forget("gks")
        learning.reload()
        #expect(learning.pending.isEmpty)
        #expect(learning.learned == ["rk": .korean])

        learning.forgetAll()
        #expect(LearningEngine(base: Fixed(language: .english), storeURL: url).learned.isEmpty)
    }
}
