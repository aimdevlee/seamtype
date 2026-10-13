import Cocoa
import SQLite3

/// The user's text replacements (System Settings → Keyboard → Text Replacements).
///
/// AppKit's list (`NSSpellChecker.userReplacementsDictionary`, mirrored into the global defaults)
/// leaves out entries whose shortcut is a kana reading (ぐー): macOS keeps those for the Japanese
/// input method's candidates, and keeps one phrase per shortcut where the pane allows several.
/// So the entries are also read from the store behind that settings pane, read-only, and only
/// again when it changed.
@MainActor
final class TextReplacements {
    static let shared = TextReplacements()

    private let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/KeyboardServices/TextReplacements.db")
    private var cached: (stamp: [Date], entries: [String: [String]])?

    /// Every phrase of each shortcut, oldest entry first.
    var entries: [String: [String]] {
        var all = storeEntries()
        for (shortcut, phrase) in NSSpellChecker.shared.userReplacementsDictionary where !(all[shortcut]?.contains(phrase) ?? false) {
            all[shortcut, default: []].append(phrase)
        }
        return all
    }

    private func storeEntries() -> [String: [String]] {
        // The store writes through its -wal file first.
        let stamp = [store.path, store.path + "-wal"].map {
            (try? FileManager.default.attributesOfItem(atPath: $0)[.modificationDate] as? Date) ?? .distantPast
        }
        if let cached, cached.stamp == stamp { return cached.entries }
        let entries = Self.read(store)
        cached = (stamp, entries)
        return entries
    }

    private static func read(_ url: URL) -> [String: [String]] {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [:] }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED = 0 ORDER BY ZTIMESTAMP"
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { return [:] }
        var entries: [String: [String]] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let shortcut = sqlite3_column_text(statement, 0), let phrase = sqlite3_column_text(statement, 1) else { continue }
            let key = String(cString: shortcut), text = String(cString: phrase)
            if !key.isEmpty, !(entries[key]?.contains(text) ?? false) { entries[key, default: []].append(text) }
        }
        return entries
    }
}
