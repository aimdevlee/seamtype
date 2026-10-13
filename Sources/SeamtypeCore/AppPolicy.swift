import Foundation

/// How eagerly Seamtype converts in a given app.
public struct AppPolicy: Codable, Equatable, Sendable {
    /// When false, Seamtype passes every key through (plain English typing).
    public var enabled: Bool
    /// Convert away from the typed English letters only when the engine is at least
    /// this confident. On the held-out set, raising it above 0.5 left more Korean
    /// words as letters without catching more wrong conversions, so it only pays
    /// off where a wrong conversion is expensive (terminals, editors).
    public var conversionThreshold: Double
    /// Esc belongs to the app (vim, editors): it commits the word and goes through, and
    /// ⇧Esc switches the word's language instead. (Inside a vim that reports its modes, Esc is
    /// vim's whatever this says.)
    public var escapeToApp: Bool
    /// Space doesn't finish the word: the word and its space stay underlined until the next word
    /// starts (Return, Tab, punctuation and shortcuts finish it too). Esc still changes it, and
    /// Delete takes back just the space. For terminals, which can't hand a finished word back for
    /// a change. The app then never sees the Space key, so its text replacements don't fire.
    public var holdSpace: Bool
    /// Full-width digits and spaces after Japanese (when turned on in the settings) apply here;
    /// false keeps them half-width in this app (a terminal, a code editor).
    public var fullWidth: Bool

    public init(enabled: Bool = true, conversionThreshold: Double = 0.5, escapeToApp: Bool = false,
                holdSpace: Bool = false, fullWidth: Bool = true) {
        self.enabled = enabled
        self.conversionThreshold = conversionThreshold
        self.escapeToApp = escapeToApp
        self.holdSpace = holdSpace
        self.fullWidth = fullWidth
    }

    public static let standard = AppPolicy()
    /// The "strict" choice: convert only when quite sure (short shell commands and identifiers
    /// collide with Hangul easily).
    public static let strictThreshold = 0.97

    /// An `apps.json` entry: only the keys it names replace the default policy, so
    /// `{"conversionThreshold": 0.97}` keeps whatever the default says about Esc.
    public struct Override: Codable, Equatable, Sendable {
        public var enabled: Bool?
        public var conversionThreshold: Double?
        public var escapeToApp: Bool?
        public var holdSpace: Bool?
        public var fullWidth: Bool?

        public init(enabled: Bool? = nil, conversionThreshold: Double? = nil, escapeToApp: Bool? = nil,
                    holdSpace: Bool? = nil, fullWidth: Bool? = nil) {
            self.enabled = enabled
            self.conversionThreshold = conversionThreshold
            self.escapeToApp = escapeToApp
            self.holdSpace = holdSpace
            self.fullWidth = fullWidth
        }

        /// The keys of `policy` that differ from `base`.
        init(difference policy: AppPolicy, from base: AppPolicy) {
            self.init(enabled: policy.enabled == base.enabled ? nil : policy.enabled,
                      conversionThreshold: policy.conversionThreshold == base.conversionThreshold ? nil : policy.conversionThreshold,
                      escapeToApp: policy.escapeToApp == base.escapeToApp ? nil : policy.escapeToApp,
                      holdSpace: policy.holdSpace == base.holdSpace ? nil : policy.holdSpace,
                      fullWidth: policy.fullWidth == base.fullWidth ? nil : policy.fullWidth)
        }

        func applied(to base: AppPolicy) -> AppPolicy {
            AppPolicy(enabled: enabled ?? base.enabled,
                      conversionThreshold: conversionThreshold ?? base.conversionThreshold,
                      escapeToApp: escapeToApp ?? base.escapeToApp,
                      holdSpace: holdSpace ?? base.holdSpace,
                      fullWidth: fullWidth ?? base.fullWidth)
        }
    }
}

/// Picks the policy for an app from `~/Library/Application Support/Seamtype/apps.json`:
/// the `"*"` entry is the user's default, and an app's entry changes only the keys it names.
/// Keys ending in "." match as a prefix (e.g. "com.jetbrains."). No app is listed unless the
/// user lists it.
public struct AppPolicies: Sendable {
    public var overrides: [String: AppPolicy.Override]

    /// The `apps.json` key of the default policy.
    public static let defaultKey = "*"

    public init(overrides: [String: AppPolicy.Override] = [:]) {
        self.overrides = overrides
    }

    public static var storeURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Seamtype/apps.json")
    }

    /// Loads user overrides; a missing or unreadable file means none.
    public static func load(from url: URL? = AppPolicies.storeURL) -> AppPolicies {
        guard let url, let data = try? Data(contentsOf: url),
              let overrides = try? JSONDecoder().decode([String: AppPolicy.Override].self, from: data) else {
            return AppPolicies()
        }
        return AppPolicies(overrides: overrides)
    }

    /// What every app uses unless its own entry says otherwise.
    public var defaultPolicy: AppPolicy {
        overrides[Self.defaultKey]?.applied(to: .standard) ?? .standard
    }

    /// The apps the user listed (the default entry excluded).
    public var apps: [String] {
        overrides.keys.filter { $0 != Self.defaultKey }.sorted()
    }

    public func policy(for bundleIdentifier: String?) -> AppPolicy {
        let base = defaultPolicy
        guard let id = bundleIdentifier, id != Self.defaultKey else { return base }
        return Self.lookup(id, in: overrides.filter { $0.key != Self.defaultKey })?.applied(to: base) ?? base
    }

    /// Sets the default, naming only what differs from Seamtype's own.
    public mutating func setDefault(_ policy: AppPolicy) {
        let entry = AppPolicy.Override(difference: policy, from: .standard)
        overrides[Self.defaultKey] = entry == AppPolicy.Override() ? nil : entry
    }

    /// Sets exactly which keys the app's entry names (nil: follows the default); the app stays
    /// listed even when it names none.
    public mutating func setEntry(_ entry: AppPolicy.Override, for bundleIdentifier: String) {
        guard bundleIdentifier != Self.defaultKey else { return }
        overrides[bundleIdentifier] = entry
    }

    /// Lists the app (if it wasn't) and makes it behave as `policy`, naming only the keys that
    /// differ from the default, so the rest keeps following it. The entry stays even when
    /// nothing differs: the user added the app, only removing it takes it off the list.
    public mutating func set(_ policy: AppPolicy, for bundleIdentifier: String) {
        guard bundleIdentifier != Self.defaultKey else { return setDefault(policy) }
        overrides[bundleIdentifier] = AppPolicy.Override(difference: policy, from: defaultPolicy)
    }

    /// Writes the entries to `apps.json`. Callers load, change and save, so entries for other
    /// apps are kept as they were.
    public func save(to url: URL? = AppPolicies.storeURL) throws {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(overrides).write(to: url, options: .atomic)
    }

    private static func lookup<T>(_ id: String, in table: [String: T]) -> T? {
        if let exact = table[id] { return exact }
        return table.first(where: { $0.key.hasSuffix(".") && id.hasPrefix($0.key) })?.value
    }
}
