import Foundation

/// User settings from `~/Library/Application Support/Seamtype/settings.json`:
///
///     { "japanese": true, "liveConversion": true }
///
/// A missing file or key means the default; unknown keys are ignored (and kept on save).
public struct Settings: Codable, Equatable, Sendable {
    /// Detect romaji Japanese and convert it (kana preview, Space for kanji).
    public var japanese: Bool = false
    /// With Japanese on: show (and commit) the top kanji candidate while typing, like macOS
    /// Live Conversion. Space opens the other candidates, Esc shows the kana.
    public var liveConversion: Bool = false
    /// A right ⌘ tap pauses Seamtype in the text field (keys go through as typed).
    public var rightCommandPause: Bool = true
    /// Return on an underlined word only confirms it, like a Japanese IME; off, the app gets the
    /// Return too (a Japanese phrase is still only confirmed).
    public var returnConfirmsOnly: Bool = true
    /// Once a day, ask GitHub for the latest release's version (nothing else is sent), and offer
    /// it in the input menu and About when it is newer.
    public var checkForUpdates: Bool = true
    /// Kanji conversion: "apple", macOS's own Japanese engine (AzooKey where it can't be loaded),
    /// or "azooKey".
    public var japaneseEngine: String = "apple"
    /// With Japanese on: digits after Japanese text are part of it, full-width (１２３); Space offers 123.
    public var fullWidthDigits: Bool = false
    /// With Japanese on: a space after Japanese text is full-width (⇧Space types the other width).
    public var fullWidthSpace: Bool = false

    public init(japanese: Bool = false, liveConversion: Bool = false, rightCommandPause: Bool = true,
                returnConfirmsOnly: Bool = true, checkForUpdates: Bool = true, japaneseEngine: String = "apple",
                fullWidthDigits: Bool = false, fullWidthSpace: Bool = false) {
        self.fullWidthDigits = fullWidthDigits
        self.fullWidthSpace = fullWidthSpace
        self.japanese = japanese
        self.liveConversion = liveConversion
        self.rightCommandPause = rightCommandPause
        self.returnConfirmsOnly = returnConfirmsOnly
        self.checkForUpdates = checkForUpdates
        self.japaneseEngine = japaneseEngine
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        japanese = try c.decodeIfPresent(Bool.self, forKey: .japanese) ?? false
        liveConversion = try c.decodeIfPresent(Bool.self, forKey: .liveConversion) ?? false
        rightCommandPause = try c.decodeIfPresent(Bool.self, forKey: .rightCommandPause) ?? true
        returnConfirmsOnly = try c.decodeIfPresent(Bool.self, forKey: .returnConfirmsOnly) ?? true
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        japaneseEngine = try c.decodeIfPresent(String.self, forKey: .japaneseEngine) ?? "apple"
        fullWidthDigits = try c.decodeIfPresent(Bool.self, forKey: .fullWidthDigits) ?? false
        fullWidthSpace = try c.decodeIfPresent(Bool.self, forKey: .fullWidthSpace) ?? false
    }

    public static var storeURL: URL? {
        SupportDirectory.url?.appendingPathComponent("settings.json")
    }

    public static func load(from url: URL? = Settings.storeURL) -> Settings {
        guard let url, let data = try? Data(contentsOf: url),
              let settings = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return settings
    }

    /// Writes these values over the file's, keeping any keys this version doesn't know.
    public func save(to url: URL? = Settings.storeURL) throws {
        guard let url else { return }
        var object = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let mine = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] ?? [:]
        object.merge(mine) { _, new in new }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
