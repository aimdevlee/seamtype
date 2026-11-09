import Foundation

/// How often the user typed each word and sentence, for `Completion` to offer the usual ones
/// first: `typed.json`, a weight per text that halves every `halfLife` days unused. A sentence
/// is kept on disk only once typed twice; typed once it is only remembered until the input
/// method quits, so a one-off line never lands in the file.
public final class TypedHistory: @unchecked Sendable {
    public static let shared = TypedHistory(url: SupportDirectory.url?.appendingPathComponent("typed.json"))

    struct Entry: Codable { var weight: Double; var day: Double }
    struct Store: Codable { var words: [String: Entry] = [:]; var sentences: [String: Entry] = [:] }

    static let halfLife = 14.0
    static let maxWords = 3000
    static let maxSentences = 500
    static let secondsPerDay = 86_400.0

    private let url: URL?
    private var store = Store()
    private var typedOnce: Set<String> = []

    /// `url` nil: kept in memory only (tests).
    public init(url: URL?) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url) else { return }
        if let read = try? JSONDecoder().decode(Store.self, from: data) { store = read } else { SupportDirectory.setAside(url) }
    }

    public func noteWord(_ word: String, now: Date = Date()) {
        Self.bump(&store.words, word, now: now, limit: Self.maxWords)
        unsaved += 1
        if unsaved >= Self.wordsPerSave { save() }
    }

    /// Words are written every so many, not on each one.
    static let wordsPerSave = 20
    private var unsaved = 0

    public func noteSentence(_ sentence: String, now: Date = Date()) {
        guard store.sentences[sentence] != nil || !typedOnce.insert(sentence).inserted else { return }
        typedOnce.remove(sentence)
        Self.bump(&store.sentences, sentence, now: now, limit: Self.maxSentences)
        save()
    }

    /// Sentences, then words, most used first.
    func ranked(now: Date = Date()) -> (sentences: [String], words: [String]) {
        func order(_ entries: [String: Entry]) -> [String] {
            entries.map { ($0.key, Self.weight($0.value, now: now)) }.sorted { ($0.1, $1.0) > ($1.1, $0.0) }.map(\.0)
        }
        return (order(store.sentences), order(store.words))
    }

    public func save() {
        unsaved = 0
        guard let url, let data = try? JSONEncoder().encode(store) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func weight(_ entry: Entry, now: Date) -> Double {
        entry.weight * pow(0.5, (now.timeIntervalSince1970 / secondsPerDay - entry.day) / halfLife)
    }

    private static func bump(_ entries: inout [String: Entry], _ text: String, now: Date, limit: Int) {
        let day = now.timeIntervalSince1970 / secondsPerDay
        entries[text] = Entry(weight: (entries[text].map { weight($0, now: now) } ?? 0) + 1, day: day)
        // ponytail: sorts the whole table when full; fine at a few thousand entries.
        guard entries.count > limit else { return }
        let dropped = entries.map { ($0.key, weight($0.value, now: now)) }.sorted { $0.1 < $1.1 }.prefix(entries.count - limit)
        for (key, _) in dropped { entries[key] = nil }
    }
}
