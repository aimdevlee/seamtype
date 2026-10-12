import SeamtypeCore
import Cocoa
import SwiftUI

/// The settings window runs as its own process (`Seamtype --settings <tab>`): the input method
/// itself is a background-only app that can't take keyboard focus for a window. It edits the
/// files in the support folder and tells the input method to read them again.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, typing, apps, learning, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L("General")
        case .typing: return L("Try Typing")
        case .apps: return L("Apps")
        case .learning: return L("Learning")
        case .about: return L("About")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .typing: return "keyboard"
        case .apps: return "macwindow"
        case .learning: return "book.closed"
        case .about: return "info.circle"
        }
    }
}

enum SettingsLauncher {
    static let showTab = Notification.Name("com.aimdevlee.inputmethod.Seamtype.showSettings")

    /// Brings the open settings window to `tab`, or starts one.
    static func open(tab: SettingsTab) {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me }
        if let window = others.first {
            DistributedNotificationCenter.default().postNotificationName(showTab, object: tab.rawValue,
                                                                        userInfo: nil, deliverImmediately: true)
            window.activate()
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--settings", tab.rawValue]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            if let error { NSLog("Seamtype: could not open settings: %@", error.localizedDescription) }
        }
    }
}

enum AppName {
    static func of(_ bundleIdentifier: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleIdentifier
    }

    static func icon(_ bundleIdentifier: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: - App

@MainActor
func runSettingsApp(tab: SettingsTab) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    if let icon = SeamMark.appIcon() { app.applicationIconImage = icon }
    let model = SettingsModel(tab: tab)
    let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
    window.title = L("Seamtype Settings")
    window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
    window.setContentSize(NSSize(width: 860, height: 640))
    window.center()
    let delegate = SettingsAppDelegate()
    app.delegate = delegate
    app.mainMenu = SettingsAppDelegate.mainMenu()
    window.makeKeyAndOrderFront(nil)
    // Front even if macOS doesn't let this (background-only) bundle activate.
    window.orderFrontRegardless()
    app.activate(ignoringOtherApps: true)

    DistributedNotificationCenter.default().addObserver(forName: SettingsLauncher.showTab, object: nil, queue: .main) { note in
        let tab = (note.object as? String).flatMap(SettingsTab.init(rawValue:))
        MainActor.assumeIsolated {
            if let tab { model.tab = tab }
            window.makeKeyAndOrderFront(nil)
        }
    }
    // The input menu may have changed things while the window was in the background.
    NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { model.reload() }
    }
    withExtendedLifetime((delegate, window)) { app.run() }
    exit(0)
}

private final class SettingsAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Quit, close and the text-editing commands (the search field needs copy and paste).
    static func mainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: L("Quit Seamtype Settings"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)
        let edit = NSMenuItem()
        edit.submenu = NSMenu(title: L("Edit"))
        edit.submenu?.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        edit.submenu?.addItem(withTitle: L("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.submenu?.addItem(withTitle: L("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.submenu?.addItem(withTitle: L("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.submenu?.addItem(withTitle: L("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(edit)
        return main
    }
}

// MARK: - Model

/// The support folder's files as the window shows them. Every change is written at once and
/// the input method is told to pick it up.
@MainActor
final class SettingsModel: ObservableObject {
    struct AppRow: Identifiable {
        let id: String
        let name: String
        /// What the app's own entry sets; nil fields follow the default.
        let entry: AppPolicy.Override
    }

    struct Word: Identifiable {
        var id: String { keys }
        let keys: String
        let text: String
        let language: Language
    }

    @Published var tab: SettingsTab
    @Published private(set) var settings = SeamtypeCore.Settings.load()
    @Published private(set) var defaultPolicy = AppPolicy.standard
    @Published private(set) var apps: [AppRow] = []
    @Published private(set) var learned: [Word] = []
    @Published private(set) var pending: [Word] = []

    private let lexicon = LearningEngine(base: NoEngine())

    init(tab: SettingsTab) {
        self.tab = tab
        reload()
    }

    func reload() {
        settings = SeamtypeCore.Settings.load()
        lexicon.reload()
        let words = { (map: [String: Language]) in
            map.map { Word(keys: $0.key, text: NoEngine().render($0.key, as: $0.value), language: $0.value) }
                .sorted { $0.keys < $1.keys }
        }
        learned = words(lexicon.learned)
        pending = words(lexicon.pending)
        let policies = AppPolicies.load()
        defaultPolicy = policies.defaultPolicy
        apps = policies.apps
            .map { AppRow(id: $0, name: AppName.of($0), entry: policies.overrides[$0] ?? AppPolicy.Override()) }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private func changed(kanjiReset: Bool = false) {
        SettingsNotice.post(kanjiReset: kanjiReset)
        reload()
    }

    // General

    func set<T>(_ key: WritableKeyPath<SeamtypeCore.Settings, T>, _ value: T) {
        var new = settings
        new[keyPath: key] = value
        do { try new.save() } catch { NSLog("Seamtype: could not save settings: %@", error.localizedDescription) }
        changed()
    }

    func resetKanji() {
        if let memory = AzooKeyConverter.memoryURL {
            for item in (try? FileManager.default.contentsOfDirectory(at: memory, includingPropertiesForKeys: nil)) ?? [] {
                try? FileManager.default.removeItem(at: item)
            }
        }
        changed(kanjiReset: true)
    }

    // Apps

    func setDefault(_ change: (inout AppPolicy) -> Void) {
        var policies = AppPolicies.load()
        var policy = policies.defaultPolicy
        change(&policy)
        policies.setDefault(policy)
        try? policies.save()
        changed()
    }

    func setEntry(for app: String, _ change: (inout AppPolicy.Override) -> Void) {
        var policies = AppPolicies.load()
        var entry = policies.overrides[app] ?? AppPolicy.Override()
        change(&entry)
        policies.setEntry(entry, for: app)
        try? policies.save()
        changed()
    }

    /// Takes apps off the list: they follow the default again.
    func remove(_ ids: Set<String>) {
        var policies = AppPolicies.load()
        for id in ids { policies.overrides[id] = nil }
        try? policies.save()
        changed()
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Add")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        var policies = AppPolicies.load()
        guard policies.overrides[id] == nil else { return }
        // Starts out following the default; the row's menus change it from there.
        policies.setEntry(AppPolicy.Override(), for: id)
        try? policies.save()
        changed()
    }

    // Learning

    func forget(_ keys: String) {
        lexicon.forget(keys)
        changed()
    }

    func forgetAll() {
        lexicon.forgetAll()
        changed()
    }
}

/// Lets the window read and edit lexicon.json through `LearningEngine` without loading models.
private struct NoEngine: DecisionEngine {
    func decide(_ keys: String, context: DecisionContext) -> Decision {
        Decision(language: .english, confidence: 0.5, output: keys, explanation: "")
    }
}

// MARK: - Shared pieces

private enum Strictness {
    static func name(_ threshold: Double) -> String {
        switch threshold {
        case AppPolicy.strictThreshold: return L("Strict")
        case AppPolicy.standard.conversionThreshold: return L("Normal")
        default: return String(format: "%.2f", threshold)
        }
    }
}

private func escapeName(_ toApp: Bool) -> String { toApp ? L("Send to app") : L("Switch language") }

/// What the Esc choice does, shown under the picker.
private func escapeExplanation(_ toApp: Bool) -> String {
    toApp ? L("Esc finishes the word and goes to the app. ⇧Esc changes the language.")
          : L("Esc changes the word you're typing, or the one just typed, to another language. The app doesn't get that Esc.")
}

private func strictnessExplanation(_ threshold: Double) -> String {
    threshold >= AppPolicy.strictThreshold
        ? L("Converts only words that are clearly Korean or Japanese, so short commands stay as typed (gst stays gst). For terminals.")
        : L("Converts a word when it reads more like Korean or Japanese than English (gst → ㅎㄴㅅ).")
}

extension Language {
    var displayName: String {
        switch self {
        case .english: return L("English")
        case .korean: return L("Korean")
        case .mixed: return L("Mixed")
        case .japanese: return L("Japanese")
        }
    }

    var tint: Color {
        switch self {
        case .english: return .gray
        case .korean: return .blue
        case .mixed: return .orange
        case .japanese: return .red
        }
    }
}

/// A → 아 → あ (all read "a") one after another in place, then all of them at once, cut into
/// rows like the menu-bar icon: the top of A, the middle of 아, the bottom of あ. Reduce Motion
/// shows only the joined mark.
struct SeamMark: View {
    var height: CGFloat = 96
    /// Just the joined mark, for a picture (the app icon): no animation.
    var still = false
    /// Fixed colors for a picture; nil follows the appearance.
    var plateColor: Color? = nil
    var letterColor: Color? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = 0

    init(height: CGFloat = 96, still: Bool = false, plateColor: Color? = nil, letterColor: Color? = nil) {
        self.height = height
        self.still = still
        self.plateColor = plateColor
        self.letterColor = letterColor
        _stage = State(initialValue: still ? Self.all.count : 0)
    }

    /// The app icon: the joined mark on a squircle, drawn at launch (the signed bundle can't
    /// carry one that changes, and an input method has none of its own).
    @MainActor static func appIcon() -> NSImage? {
        let ink = Color(red: 0.11, green: 0.11, blue: 0.12), paper = Color(red: 0.95, green: 0.95, blue: 0.96)
        let icon = ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous).fill(ink)
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            SeamMark(height: 560, still: true, plateColor: ink, letterColor: paper)
        }
        .frame(width: 1024, height: 1024)
        let renderer = ImageRenderer(content: icon)
        renderer.scale = 1
        return renderer.nsImage
    }

    private static let all: [(String, CGFloat)] = [("A", 0.64), ("아", 0.6), ("あ", 0.6)]
    private var letters: [(String, CGFloat)] { Self.all }
    /// Letters one by one, then the joined mark (the last stage).
    private var stages: Int { letters.count + 1 }
    private var joined: Int { letters.count }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: height * 0.28, style: .continuous).fill(plateColor ?? .primary)
            Group {
                if stage == joined { joinedMark } else { letter(letters[stage]) }
            }
            .id(stage)
            .transition(.asymmetric(
                insertion: .scale(scale: 1.06).combined(with: .opacity).combined(with: .modifier(active: Blur(radius: 2), identity: Blur(radius: 0))),
                removal: .scale(scale: 0.94).combined(with: .opacity).combined(with: .modifier(active: Blur(radius: 2), identity: Blur(radius: 0)))))
        }
        .frame(width: height * 1.25, height: height)
        .task(id: reduceMotion) {
            guard !reduceMotion, !still else { stage = joined; return }
            stage = 0
            while !Task.isCancelled {
                // The joined mark stays a little longer: it's where the sequence lands.
                try? await Task.sleep(for: .seconds(stage == joined ? 3.4 : 2.2))
                if Task.isCancelled { break }
                // Slow and even (sine-like ease in and out): the letters cross over each other.
                withAnimation(.timingCurve(0.37, 0, 0.63, 1, duration: 1.2)) {
                    stage = (stage + 1) % stages
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func letter(_ item: (String, CGFloat)) -> some View {
        Text(verbatim: item.0)
            .font(.system(size: height * item.1, weight: .heavy, design: .rounded))
            .foregroundStyle(letterColor ?? Color(nsColor: .windowBackgroundColor))
    }

    /// Each letter shows only in its own row of the letters' height, with a thin gap between rows.
    private var joinedMark: some View {
        // Letters grown so their outlines fill the rows, as in the menu-bar icon.
        let band = height * 0.62, gap = height * 0.03, grow: CGFloat = 1.32
        let row = (band - gap * CGFloat(letters.count - 1)) / CGFloat(letters.count)
        return ZStack {
            ForEach(Array(letters.enumerated()), id: \.offset) { i, item in
                letter(item)
                    .scaleEffect(grow)
                    .frame(width: height * 1.25, height: height)
                    .mask {
                        Rectangle()
                            .frame(height: row)
                            .offset(y: -band / 2 + row / 2 + CGFloat(i) * (row + gap) + height * 0.01)
                    }
            }
        }
    }

    private struct Blur: ViewModifier {
        let radius: CGFloat
        func body(content: Content) -> some View { content.blur(radius: radius) }
    }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { model.tab }, set: { if let tab = $0 { model.tab = tab } })) { tab in
                Label(tab.title, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            Group {
                switch model.tab {
                case .general: GeneralPane(model: model)
                case .typing: TypingPane(model: model)
                case .apps: AppsPane(model: model)
                case .learning: LearningPane(model: model)
                case .about: AboutPane()
                }
            }
            .navigationTitle(model.tab.title)
        }
        .frame(width: 860, height: 640)
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var model: SettingsModel
    @State private var confirmKanji = false

    private func binding(_ key: WritableKeyPath<SeamtypeCore.Settings, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: key] }, set: { model.set(key, $0) })
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("Type on the English layout; each word comes out in the language you meant."))
                        .font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Example(keys: "dkssud githubdp", output: "안녕 github에")
                        Example(keys: "hello TextEditdptj", output: "hello TextEdit에서")
                        if model.settings.japanese {
                            Example(keys: "kyouha ␣", output: "今日は")
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section(L("Languages")) {
                LabeledContent(L("Korean · English")) { Text(L("Always on")).foregroundStyle(.secondary) }
                Toggle(isOn: binding(\.japanese)) {
                    Text(L("Japanese"))
                    Text(L("Off by default. Turn on to type Japanese with romaji; Space converts to kanji."))
                }
                Group {
                    Toggle(isOn: binding(\.liveConversion)) {
                        Text(L("Live conversion"))
                        Text(L("Shows the top kanji candidate as you type."))
                    }
                    LabeledContent {
                        Button(L("Reset…")) { confirmKanji = true }
                    } label: {
                        Text(L("Kanji candidate order"))
                        Text(L("Kanji you pick in the candidate window come first next time."))
                    }
                }
                .padding(.leading, 18)
                .disabled(!model.settings.japanese)
            }
            Section(L("When a word comes out wrong")) {
                LabeledContent {
                    Text(verbatim: "Esc").foregroundStyle(.secondary)
                } label: {
                    Text(L("Switch its language"))
                    Text(L("While typing, or right after the word. ⇧Esc in apps where Esc goes to the app."))
                }
                LabeledContent {
                    Button(L("Show Remembered Words")) { model.tab = .learning }
                } label: {
                    Text(L("Remembering"))
                    Text(L("Correct the same word the same way twice and Seamtype keeps it."))
                }
            }
            Section(L("Keys")) {
                Toggle(isOn: binding(\.returnConfirmsOnly)) {
                    Text(L("Return only confirms"))
                    Text(L("Return on an underlined English or Korean word confirms it; press it again for a new line or to send. Off, the app gets that Return too. Japanese is always only confirmed."))
                }
                Toggle(isOn: binding(\.rightCommandPause)) {
                    Text(L("Right ⌘ pauses"))
                    Text(L("Tap right ⌘ on its own and keys go through as typed in that text field, for hjkl in terminal programs. Tap again, or move to another field, to resume."))
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(L("Reset the kanji candidate order?"), isPresented: $confirmKanji) {
            Button(L("Reset"), role: .destructive) { model.resetKanji() }
        } message: {
            Text(L("Kanji you picked before won't come first anymore. Remembered words stay."))
        }
    }
}

private struct Example: View {
    let keys: String
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: keys).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            Text(verbatim: output).font(.body.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Apps

private struct AppsPane: View {
    @ObservedObject var model: SettingsModel
    @State private var selection = Set<String>()

    var body: some View {
        Form {
            Section(L("Default — every app")) {
                Toggle(isOn: Binding(
                    get: { model.defaultPolicy.enabled },
                    set: { value in model.setDefault { $0.enabled = value } })) {
                    Text(L("Convert words"))
                    Text(L("Off: keys go to the app as typed, as with the ABC layout."))
                }
                Group {
                    ChoiceRow(title: L("Conversion"),
                              explanation: strictnessExplanation(model.defaultPolicy.conversionThreshold)) {
                        Picker(L("Conversion"), selection: Binding(
                            get: { model.defaultPolicy.conversionThreshold },
                            set: { value in model.setDefault { $0.conversionThreshold = value } })) {
                            Text(L("Normal")).tag(AppPolicy.standard.conversionThreshold)
                            Text(L("Strict")).tag(AppPolicy.strictThreshold)
                        }
                    }
                    ChoiceRow(title: L("Esc key"), explanation: escapeExplanation(model.defaultPolicy.escapeToApp)) {
                        Picker(L("Esc key"), selection: Binding(
                            get: { model.defaultPolicy.escapeToApp },
                            set: { value in model.setDefault { $0.escapeToApp = value } })) {
                            Text(L("Switch language")).tag(false)
                            Text(L("Send to app")).tag(true)
                        }
                    }
                }
                // Only matter while words are converted.
                .padding(.leading, 18)
                .disabled(!model.defaultPolicy.enabled)
            }
            Section {
                if model.apps.isEmpty {
                    Text(L("None. Add an app that should work differently."))
                        .foregroundStyle(.secondary)
                } else {
                    AppColumnsHeader()
                    ForEach(model.apps) { row in
                        AppRowView(row: row, defaultPolicy: model.defaultPolicy, model: model,
                                   selected: selection.contains(row.id)) {
                            if selection.contains(row.id) { selection.remove(row.id) } else { selection = [row.id] }
                        }
                    }
                }
            } header: {
                Text(L("Exceptions — only apps that differ"))
            } footer: {
                HStack(spacing: 10) {
                    ControlGroup {
                        Button { model.addApp() } label: { Image(systemName: "plus") }
                            .accessibilityLabel(L("Add App"))
                        Button { model.remove(selection); selection = [] } label: { Image(systemName: "minus") }
                            .accessibilityLabel(L("Remove App"))
                            .disabled(selection.isEmpty)
                    }
                    .fixedSize()
                    Text(L("“Default” follows the setting above; anything else applies to this app only."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppRowView: View {
    let row: SettingsModel.AppRow
    let defaultPolicy: AppPolicy
    @ObservedObject var model: SettingsModel
    let selected: Bool
    let select: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: select) {
                HStack(spacing: 8) {
                    if let icon = AppName.icon(row.id) {
                        Image(nsImage: icon).resizable().frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "app.dashed").frame(width: 22, height: 22)
                    }
                    Text(row.name).lineLimit(1).truncationMode(.middle).help(row.name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            FieldMenu(own: row.entry.enabled.map { $0 ? L("On") : L("Off") },
                      inherited: defaultPolicy.enabled ? L("On") : L("Off"),
                      choices: [(L("On"), true), (L("Off"), false)]) { value in
                model.setEntry(for: row.id) { $0.enabled = value }
            }
            .frame(width: AppColumns.enabled, alignment: .leading)
            Group {
                FieldMenu(own: row.entry.conversionThreshold.map(Strictness.name),
                          inherited: Strictness.name(defaultPolicy.conversionThreshold),
                          choices: [(L("Normal"), AppPolicy.standard.conversionThreshold), (L("Strict"), AppPolicy.strictThreshold)]) { value in
                    model.setEntry(for: row.id) { $0.conversionThreshold = value }
                }
                .frame(width: AppColumns.conversion, alignment: .leading)
                FieldMenu(own: row.entry.escapeToApp.map(escapeName),
                          inherited: escapeName(defaultPolicy.escapeToApp),
                          choices: [(L("Switch language"), false), (L("Send to app"), true)]) { value in
                    model.setEntry(for: row.id) { $0.escapeToApp = value }
                }
                .frame(width: AppColumns.escape, alignment: .leading)
            }
            .disabled(!(row.entry.enabled ?? defaultPolicy.enabled))
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        // A grouped form ignores listRowBackground, so the selection is drawn on the row itself.
        .background(selected ? Color.accentColor.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, -6)
    }
}

/// A setting with a segmented choice on its title line and what the current choice does under
/// it, across the whole row (a long explanation beside the picker would push it onto its own line).
private struct ChoiceRow<Choice: View>: View {
    let title: String
    let explanation: String
    @ViewBuilder let choice: Choice

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                choice.pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            Text(explanation)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Column widths shared by the exceptions' header and rows.
private enum AppColumns {
    static let conversion: CGFloat = 140
    static let escape: CGFloat = 190
    static let enabled: CGFloat = 100
}

/// Names the exceptions' columns after the default settings above them.
private struct AppColumnsHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text(L("App")).frame(maxWidth: .infinity, alignment: .leading)
            Text(L("Convert words")).frame(width: AppColumns.enabled, alignment: .leading)
            Text(L("Conversion")).frame(width: AppColumns.conversion, alignment: .leading)
            Text(L("Esc key")).frame(width: AppColumns.escape, alignment: .leading)
        }
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
        .accessibilityHidden(true)
    }
}

/// One per-app value: the app's own, or "Default · <value>" while it follows the default. The
/// difference is in the words: a borderless menu's label shows no color or weight.
private struct FieldMenu<Value>: View {
    let own: String?
    let inherited: String
    let choices: [(String, Value)]
    let set: (Value?) -> Void

    var body: some View {
        Menu {
            Button(L("Default (%@)", inherited)) { set(nil) }
            Divider()
            ForEach(choices.indices, id: \.self) { i in
                Button(choices[i].0) { set(choices[i].1) }
            }
        } label: {
            Text(own ?? L("Default · %@", inherited))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - Learning

private struct LearningPane: View {
    @ObservedObject var model: SettingsModel
    @State private var showPending = false
    @State private var search = ""
    @State private var confirmForgetAll = false

    private var words: [SettingsModel.Word] {
        (showPending ? model.pending : model.learned).filter {
            search.isEmpty || $0.keys.localizedCaseInsensitiveContains(search) || $0.text.contains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Picker(L("List"), selection: $showPending) {
                    Text(L("Remembered %ld", model.learned.count)).tag(false)
                    Text(L("Corrected once %ld", model.pending.count)).tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                Spacer()
                TextField(L("Search keys or words"), text: $search)
                    .textFieldStyle(.roundedBorder).frame(width: 210)
            }
            Text(showPending ? L("Correct one of these the same way once more and Seamtype keeps it.")
                             : L("Seamtype writes these keys this way. Forget one and it decides again."))
                .font(.callout).foregroundStyle(.secondary)
            if words.isEmpty {
                EmptyList(symbol: search.isEmpty ? "text.book.closed" : "magnifyingglass",
                          title: search.isEmpty ? (showPending ? L("No words corrected once") : L("No remembered words yet"))
                                                : L("No matches"),
                          detail: search.isEmpty ? L("Press Esc on a word that came out wrong; correct it the same way twice and it's remembered here.") : nil)
            } else {
                List {
                    ForEach(words) { WordRow(word: $0, model: model) }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
            HStack {
                Spacer()
                Button(L("Forget All…"), role: .destructive) { confirmForgetAll = true }
                    .disabled(model.learned.isEmpty && model.pending.isEmpty)
            }
        }
        .padding(20)
        .confirmationDialog(L("Forget every remembered word?"), isPresented: $confirmForgetAll) {
            Button(L("Forget All"), role: .destructive) { model.forgetAll() }
        } message: {
            Text(L("Words corrected once are forgotten too. This can't be undone."))
        }
    }
}

/// In place of an empty list: what would be there, and how it fills up.
private struct EmptyList: View {
    let symbol: String
    let title: String
    let detail: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 30)).foregroundStyle(.tertiary)
            Text(title).font(.headline).foregroundStyle(.secondary)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct WordRow: View {
    let word: SettingsModel.Word
    @ObservedObject var model: SettingsModel

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: word.keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).frame(width: 170, alignment: .leading).help(word.keys)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            Text(verbatim: word.text).lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(word.language.displayName).font(.caption)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .background(word.language.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            Button { model.forget(word.keys) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.tertiary)
                .help(L("Forget"))
                .accessibilityLabel(L("Forget %@", word.keys))
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    SeamMark(height: 84)
                    Text(verbatim: "Seamtype").font(.title2.weight(.bold))
                    Text(verbatim: "흐름대로 써진다 · 流れるままに · Type as it flows")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            Section {
                LabeledContent(L("Version"), value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent(L("License"), value: "MIT")
                LabeledContent(L("Settings and learning files")) {
                    Button(L("Show in Finder")) {
                        if let url = SupportDirectory.url { NSWorkspace.shared.open(url) }
                    }
                }
                LabeledContent(L("Open source notices")) {
                    Button(L("Open")) {
                        if let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } footer: {
                Text(L("What you type never leaves this Mac: deciding words and converting kanji both happen here."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if Uninstaller.isAvailable {
                Section {
                    LabeledContent(L("Uninstall Seamtype")) {
                        Button(L("Uninstall…"), role: .destructive) { Uninstaller.confirmAndRun() }
                    }
                } footer: {
                    Text(L("Removes Seamtype from this Mac and switches to another input source. If it was installed with the installer, macOS asks for your password."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}
