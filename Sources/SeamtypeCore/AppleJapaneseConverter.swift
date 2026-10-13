import Foundation

/// macOS's own Japanese conversion engine (libmecabra, the one behind the system's Japanese input),
/// loaded at runtime. Its dictionary has what AzooKey's lacks: variant kanji (たか → 髙), English
/// spellings of names (とぅいっち → Twitch) and completions (ゆーちゅ → YouTube).
///
/// The library is private, so every function is looked up by name and `init` returns nil when one
/// is missing; the caller falls back to `AzooKeyConverter`. The engine's own learning didn't hold
/// across launches, so choices are learned here instead (Application Support/Seamtype/apple-learning.json).
@MainActor
public final class AppleJapaneseConverter: JapaneseConverter {
    private typealias Create = @convention(c) (CFDictionary) -> OpaquePointer?
    private typealias Release = @convention(c) (OpaquePointer) -> Void
    private typealias Analyze = @convention(c) (OpaquePointer, CFString, Int) -> Bool
    private typealias Next = @convention(c) (OpaquePointer) -> OpaquePointer?
    private typealias Text = @convention(c) (OpaquePointer) -> Unmanaged<CFString>?

    /// `MecabraAnalyzeString` modes: conversions of the reading, and those mixed with completions.
    private static let conversionMode = 2, predictionMode = 1

    private let engine: OpaquePointer
    private let release: Release
    private let analyze: Analyze
    private let next: Next
    private let surface: Text
    private let reading: Text
    private let learningURL: URL?
    /// Reading → texts the user chose for it, most recent first.
    private var learned: [String: [String]]
    private var unsaved = false
    public var rerankWeight: Double? = 1.0

    public init?(learning: URL? = AppleJapaneseConverter.learningURL) {
        guard let library = dlopen("/usr/lib/libmecabra.dylib", RTLD_NOW) else { return nil }
        func function<T>(_ name: String, _ type: T.Type) -> T? { dlsym(library, name).map { unsafeBitCast($0, to: type) } }
        guard let create = function("MecabraCreate", Create.self),
              let release = function("MecabraRelease", Release.self),
              let analyze = function("MecabraAnalyzeString", Analyze.self),
              let next = function("MecabraGetNextCandidate", Next.self),
              let surface = function("MecabraCandidateGetSurface", Text.self),
              let reading = function("MecabraCandidateGetAnalysisString", Text.self),
              let typeKey = dlsym(library, "kMecabraCreationInputMethodTypeKey")?.assumingMemoryBound(to: CFString.self).pointee,
              // 1: Japanese.
              let engine = create([typeKey: 1] as CFDictionary) else { return nil }
        self.engine = engine
        self.release = release
        self.analyze = analyze
        self.next = next
        self.surface = surface
        self.reading = reading
        learningURL = learning
        learned = learning.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: [String]].self, from: $0) } ?? [:]
        // An engine that loaded but converts nothing is no use either.
        guard !candidates(for: "へんかん").isEmpty else { return nil }
    }

    isolated deinit { release(engine) }

    nonisolated public static var learningURL: URL? {
        SupportDirectory.url?.appendingPathComponent("apple-learning.json")
    }

    public func candidates(for kana: String) -> [ConversionCandidate] {
        guard !kana.isEmpty else { return [] }
        // Conversions of the whole reading or of a first clause (今日は of きょうはいいてんき).
        var out: [ConversionCandidate] = []
        var seen = Set<String>()
        let conversions = results(for: kana, mode: Self.conversionMode)
        for (text, covered) in conversions
        where kana.hasPrefix(covered) && seen.insert(text + "\u{0}\(covered.count)").inserted {
            out.append(ConversionCandidate(text: text, kanaCount: covered.count))
        }
        out = AzooKeyConverter.rerank(out, kanaCount: kana.count, weight: rerankWeight)
        // The engine's mixed order after the first candidate, which stays the best conversion: it
        // puts completions where they belong (ゆーちゅ: ユーチューブ, YouTube; かんじ: 漢字 before
        // 患者). (MecabraCandidateIsPredictionCandidate always says no, so a completion is what
        // the mixed mode has that the conversions don't.)
        let converted = Set(conversions.map(\.text))
        let mixed = results(for: kana, mode: Self.predictionMode)
            .filter { $0.covered == kana && $0.text != out.first?.text }
            .map { ConversionCandidate(text: $0.text, kanaCount: kana.count, isPrediction: !converted.contains($0.text)) }
        if !out.isEmpty {
            let first = out.removeFirst()
            out = [first] + mixed + out
        }
        // The user's earlier choices for this reading first, most recent first.
        for text in (learned[kana] ?? []).reversed() {
            let chosen = out.first { $0.text == text && $0.kanaCount == kana.count } ?? ConversionCandidate(text: text, kanaCount: kana.count)
            out.removeAll { $0.text == text }
            out.insert(chosen, at: 0)
        }
        // The reading itself, in hiragana and katakana, is always available.
        for plain in [kana, RomajiComposer.katakana(kana)] where !out.contains(where: { $0.text == plain && $0.kanaCount == kana.count }) {
            out.append(ConversionCandidate(text: plain, kanaCount: kana.count))
        }
        // English typed inside the phrase stays as typed (google, not Google).
        out = out.map { ConversionCandidate(text: Self.keepingEnglish(of: kana, in: $0.text), kanaCount: $0.kanaCount, isPrediction: $0.isPrediction) }
        // The candidate window shows text only: one row per text.
        var shown = Set<String>()
        return out.filter { shown.insert($0.text).inserted }
    }

    /// `text` with each run of Latin letters from the reading spelled as it is there.
    static func keepingEnglish(of reading: String, in text: String) -> String {
        var text = text
        for word in reading.split(whereSeparator: { !($0.isASCII && $0.isLetter) }) {
            if let range = text.range(of: word, options: .caseInsensitive), text[range] != word {
                text.replaceSubrange(range, with: word)
            }
        }
        return text
    }

    /// The engine's candidates in its order: text and the reading it covers.
    private func results(for kana: String, mode: Int) -> [(text: String, covered: String)] {
        guard analyze(engine, kana as CFString, mode) else { return [] }
        var out: [(String, String)] = []
        var scanned = 0
        while scanned < 300, out.count < 60, let candidate = next(engine) {
            scanned += 1
            guard let text = surface(candidate)?.takeUnretainedValue() as String?, !text.isEmpty,
                  let covered = reading(candidate)?.takeUnretainedValue() as String?, !covered.isEmpty else { continue }
            out.append((text, covered))
        }
        return out
    }

    public func learn(_ candidate: ConversionCandidate, for kana: String) {
        let reading = String(kana.prefix(candidate.kanaCount))
        var texts = learned[reading] ?? []
        guard texts.first != candidate.text else { return }
        texts.removeAll { $0 == candidate.text }
        learned[reading] = Array(([candidate.text] + texts).prefix(5))
        unsaved = true
    }

    public func save() {
        guard unsaved, let url = learningURL, let data = try? JSONEncoder().encode(learned) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        unsaved = false
    }
}
