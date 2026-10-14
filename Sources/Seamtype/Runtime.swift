import SeamtypeCore
import Cocoa

/// What every input controller shares: settings, the decision engine and the kanji converter.
/// A change bumps `generation`; each controller then commits what it was composing and
/// continues with a fresh `InputSession` built from the new state, so nothing needs a restart.
@MainActor
final class Runtime {
    static let shared = Runtime()

    private(set) var settings: Settings
    private(set) var engine: LearningEngine
    private(set) var converter: JapaneseConverter?
    private(set) var generation = 0
    /// The controller of the text field in front, which a vim mode change is about.
    weak var active: InputController?
    /// The latest vim mode change and the app vim runs in. Vim's FocusGained can arrive before
    /// macOS activates the terminal's controller (and FocusLost after), so a controller
    /// activated in that app catches up on it.
    private(set) var lastVim: (signal: VimSignal, app: String?)?

    private init() {
        AppPolicies.migrateSwitchKey()
        settings = Settings.load()
        engine = Self.makeEngine(japanese: settings.japanese)
        converter = settings.japanese ? Self.makeConverter(settings) : nil
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: SettingsNotice.changed, object: nil, queue: .main) { note in
            let kanjiReset = note.object as? String == SettingsNotice.kanjiReset
            MainActor.assumeIsolated { Runtime.shared.reloadFromDisk(kanjiReset: kanjiReset) }
        }
        center.addObserver(forName: VimSignal.notification, object: nil, queue: .main) { note in
            guard let signal = (note.object as? String).flatMap(VimSignal.init(rawValue:)) else { return }
            let app = note.userInfo?[VimSignal.appKey] as? String
            MainActor.assumeIsolated {
                Runtime.shared.lastVim = (signal, app)
                Runtime.shared.active?.vimChanged(to: signal, from: app)
            }
        }
    }

    /// Order of authority: words the user changed with Esc (twice), then mixed-word splitting
    /// (github에, x에, hello월드, githubで), then the heuristic.
    private static func makeEngine(japanese: Bool) -> LearningEngine {
        let heuristic = HeuristicEngine(japanese: japanese ? JapaneseModel.shared : nil)
        return LearningEngine(base: SplittingEngine(base: heuristic, english: heuristic.english,
                                                    japanese: heuristic.segmenter))
    }

    /// macOS's Japanese engine unless the user chose AzooKey; AzooKey also where macOS's can't be loaded.
    private static func makeConverter(_ settings: Settings) -> JapaneseConverter? {
        if settings.japaneseEngine != "azooKey", let apple = AppleJapaneseConverter() { return apple }
        return AzooKeyConverter()
    }

    func makeSession() -> InputSession {
        let session = InputSession(engine: engine, policies: AppPolicies.load(),
                                   converter: settings.japanese ? converter : nil,
                                   japaneseEnabled: settings.japanese, liveConversion: settings.liveConversion,
                                   returnConfirmsOnly: settings.returnConfirmsOnly)
        session.replacements = textReplacements
        session.fullWidthDigits = settings.fullWidthDigits
        session.fullWidthSpace = settings.fullWidthSpace
        return session
    }

    /// The user's text replacements, read again whenever a text field becomes active, so an edit
    /// in System Settings applies without a restart.
    var textReplacements: [String: [String]] { TextReplacements.shared.entries }

    /// Saves a settings change and applies it.
    func update(_ change: (inout Settings) -> Void) {
        var new = settings
        change(&new)
        guard new != settings else { return }
        do { try new.save() } catch { NSLog("Seamtype: could not save settings: %@", error.localizedDescription) }
        apply(new)
    }

    /// Saves a change to one app's behavior and applies it.
    func updatePolicy(for app: String, _ change: (inout AppPolicy) -> Void) {
        var policies = AppPolicies.load()
        var policy = policies.policy(for: app)
        change(&policy)
        policies.set(policy, for: app)
        do { try policies.save() } catch { NSLog("Seamtype: could not save apps.json: %@", error.localizedDescription) }
        generation += 1
    }

    /// Takes the app off the list: it follows the default again.
    func removePolicy(for app: String) {
        var policies = AppPolicies.load()
        policies.overrides[app] = nil
        do { try policies.save() } catch { NSLog("Seamtype: could not save apps.json: %@", error.localizedDescription) }
        generation += 1
    }

    func undoLastLearned() {
        guard let keys = engine.lastLearned else { return }
        engine.forget(keys)
    }

    private func apply(_ new: Settings) {
        if new.japanese != settings.japanese {
            engine = Self.makeEngine(japanese: new.japanese)
        }
        if new.japanese, converter == nil || new.japaneseEngine != settings.japaneseEngine {
            converter?.save()
            converter = Self.makeConverter(new)
        }
        settings = new
        generation += 1
    }

    /// The settings window changed files: read them again.
    private func reloadFromDisk(kanjiReset: Bool) {
        if kanjiReset {
            // Drop the converter without saving, so its memory doesn't come back.
            converter = nil
            if settings.japanese { converter = Self.makeConverter(settings) }
        }
        engine.reload()
        apply(Settings.load())
        generation += 1
    }
}

/// Between the settings window (its own process) and the input method.
enum SettingsNotice {
    static let changed = Notification.Name("com.aimdevlee.inputmethod.Seamtype.settingsChanged")
    static let kanjiReset = "kanjiReset"

    static func post(kanjiReset: Bool = false) {
        DistributedNotificationCenter.default().postNotificationName(
            changed, object: kanjiReset ? Self.kanjiReset : nil, userInfo: nil, deliverImmediately: true)
    }
}
