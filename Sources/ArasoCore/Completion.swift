import Foundation

/// Words offered to finish the word being typed (Tab steps through them): first the sentences
/// and words the user types most (`TypedHistory`), then the sentences in the text around it
/// (before it, and on screen) that start that way, then the words there, most often there first;
/// then the most common listed words.
public enum Completion {
    /// How many are offered at a time.
    public static let limit = 5
    /// Shorter starts match too many words to guess from.
    static let minimumLength: [Language: Int] = [.korean: 2, .english: 2]
    /// SCOWL levels past this are words nobody wants offered.
    static let englishLevel = 35
    /// Syllables sharing an initial and vowel, one per final consonant (none first).
    static let finals: UInt32 = 28
    /// A sentence from the text is offered up to here, cut at a space.
    static let sentenceLength = 60
    static let sentenceEnds: Set<Character> = [".", "!", "?", "。", "！", "？"]
    static let wordEnds: Set<Character> = [",", ";", ":", "\"", "'", "(", ")", "[", "]", "{", "}", "…", "、"]

    /// Sorted by word; `rank` lower is more common.
    private typealias Entry = (word: String, rank: Int)

    private static let korean: [Entry] = KoreanModel.vocabularyCounts
        .filter { $0.count >= KoreanModel.commonCount }
        .map { ($0.word, -$0.count) }
        .sorted { $0.word < $1.word }

    private static let english: [Entry] = EnglishModel.shared.levels
        .filter { $0.value <= englishLevel }
        .map { ($0.key, $0.value) }
        .sorted { $0.word < $1.word }

    /// A terminal's screen as Accessibility gives it, every line padded to the window's width and
    /// drawn into boxes (Claude Code): lines of words only, box lines splitting panes apart. What
    /// is being typed is left out: the line at `caret` (UTF-16 in `raw`), or the whole box it is in.
    public static func tidyScreen(_ raw: String, caret: Int? = nil) -> String {
        let kept = caret.map { withoutTyping(raw.components(separatedBy: "\n"), caret: $0).joined(separator: "\n") } ?? raw
        return dropCellFillers(kept).unicodeScalars.map { (0x2500...0x257F).contains($0.value) ? "\n" : String($0) }.joined()
            .split(whereSeparator: \.isNewline)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// A box's edge: a run of ─ (Claude Code's input box is drawn between two).
    static let boxEdge = String(repeating: "─", count: 10)
    /// How far from the caret a box's edges are looked for.
    static let boxLines = 20

    /// `lines` without the one holding `caret`, or without the box around it: from the edge above
    /// to the edge below, with no line without words between.
    static func withoutTyping(_ lines: [String], caret: Int) -> [String] {
        var offset = 0, at = lines.count - 1
        for (i, line) in lines.enumerated() {
            let end = offset + line.utf16.count
            if caret <= end { at = i; break }
            offset = end + 1
        }
        func edge(_ range: [Int]) -> Int? {
            let stop = range.prefix(boxLines).first { lines[$0].contains(boxEdge) || !lines[$0].contains(where: \.isLetter) }
            return stop.flatMap { lines[$0].contains(boxEdge) ? $0 : nil }
        }
        var kept = lines
        if let top = edge(Array((0..<at).reversed())), let bottom = edge(Array(at + 1..<lines.count)) {
            kept.removeSubrange(top...bottom)
        } else {
            kept.remove(at: at)
        }
        return kept
    }

    /// The text before the caret without the sentence being typed: up to the last sentence end
    /// or line break.
    public static func beforeSentence(_ text: String) -> String {
        guard let end = text.lastIndex(where: { $0.isNewline || sentenceEnds.contains($0) }) else { return "" }
        return String(text[...end])
    }

    /// iTerm2 gives a wide character's second cell as NUL (지\0금\0은\0), to Accessibility and to
    /// the input method alike: without them its Korean reads as words again.
    static func dropCellFillers(_ text: String) -> String { text.replacingOccurrences(of: "\u{0}", with: "") }

    /// `context` is the text before the word, read from the app (empty where it can't be).
    /// `keys`, the word's keys as typed: words there mixing Latin and Hangul are offered by the keys
    /// that type them, whatever the word is shown as (Gak, shown as English, offers G마켓); the
    /// shown word alone never matches them (neither all Hangul nor all ASCII).
    public static func suggest(_ shown: String, as language: Language, context: String = "",
                               history: TypedHistory? = nil, keys: String = "") -> [String] {
        let context = dropCellFillers(context)
        let byKeys = typedAs(keys, in: context, history: history)
        var seen: Set<String> = [shown]
        return Array((byKeys + byShown(shown, as: language, context: context, history: history))
            .filter { seen.insert($0).inserted }.prefix(limit))
    }

    /// Words in `context` and `history` mixing Latin and Hangul whose 2-set keys start with `keys`.
    static func typedAs(_ keys: String, in context: String, history: TypedHistory?) -> [String] {
        guard keys.count >= 2 else { return [] }
        let ranked = history.map { $0.ranked().words } ?? []
        let written = context.split { $0.isWhitespace || wordEnds.contains($0) || sentenceEnds.contains($0) }
            .reversed().map(String.init)
        return byCount((ranked + written).filter { word in
            mixesLatinAndHangul(word)
                && DubeolsikLayout.keys(spelling: word).map { $0.count > keys.count && $0.hasPrefix(keys) } == true
        })
    }

    static func mixesLatinAndHangul(_ word: String) -> Bool {
        word.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
            && word.contains { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    private static func byShown(_ shown: String, as language: Language, context: String, history: TypedHistory?) -> [String] {
        guard let minimum = minimumLength[language], shown.count >= minimum,
              let last = shown.unicodeScalars.last else { return [] }
        let found: [String]
        switch language {
        case .korean:
            guard shown.allSatisfy({ ("가"..."힣").contains($0) }) else { return [] }
            // 감사하 is still on its way to 감사합니다: an open last syllable may take a final.
            let span = (last.value - 0xAC00) % finals == 0 ? finals : 1
            found = usual(in: history, from: shown, span: span) + written(in: context, from: shown, span: span)
                + listed(in: korean, from: shown, span: span)
        case .english:
            guard shown.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
            let typed = shown.lowercased()
            found = (usual(in: history, from: typed, span: 1) + written(in: context, from: typed, span: 1)
                + listed(in: english, from: typed, span: 1))
                .map { shown + $0.dropFirst(typed.count) }
        default:
            return []
        }
        return found
    }

    /// Whether `word` starts with `prefix`, its last scalar up to `span` further on.
    static func starts(_ word: String, with prefix: String, span: UInt32) -> Bool {
        let w = Array(word.unicodeScalars), p = Array(prefix.unicodeScalars)
        guard w.count >= p.count, let last = p.last, w[..<(p.count - 1)].elementsEqual(p.dropLast()) else { return false }
        return (last.value..<last.value + span).contains(w[p.count - 1].value)
    }

    /// The user's sentences, then words, whose first word starts with `prefix`, most used first.
    private static func usual(in history: TypedHistory?, from prefix: String, span: UInt32) -> [String] {
        guard let history else { return [] }
        let english = prefix.allSatisfy(\.isASCII)
        let ranked = history.ranked()
        return (ranked.sentences + ranked.words).filter {
            let first = String($0.prefix { !$0.isWhitespace && !wordEnds.contains($0) && !sentenceEnds.contains($0) })
            return starts(english ? first.lowercased() : first, with: prefix, span: span)
        }
    }

    /// The sentences, then the words, at the places in `context` a word starts with `prefix`,
    /// most often there first, then latest (English matched without case, as `prefix` is lowercased).
    private static func written(in context: String, from prefix: String, span: UInt32) -> [String] {
        let english = prefix.allSatisfy(\.isASCII)
        let text = Array(context)
        var sentences: [String] = [], words: [String] = []
        for start in text.indices.reversed() {
            // ponytail: scans every character of the context per key; the context is capped.
            guard text[start].isLetter, start == 0 || !text[start - 1].isLetter else { continue }
            let rest = text[start...]
            let wordEnd = rest.firstIndex { $0.isWhitespace || wordEnds.contains($0) || sentenceEnds.contains($0) } ?? text.endIndex
            let word = String(text[start..<wordEnd])
            guard starts(english ? word.lowercased() : word, with: prefix, span: span) else { continue }
            var end = rest.firstIndex { $0.isNewline || sentenceEnds.contains($0) }.map { text[$0].isNewline ? $0 : $0 + 1 } ?? text.endIndex
            if end - start > sentenceLength {
                end = text[start..<start + sentenceLength].lastIndex(where: \.isWhitespace) ?? wordEnd
            }
            let sentence = String(text[start..<end]).trimmingCharacters(in: .whitespaces)
            if sentence != word { sentences.append(sentence) }
            words.append(word)
        }
        return byCount(sentences) + byCount(words)
    }

    /// `texts` (latest first) once each, the most repeated first.
    static func byCount(_ texts: [String]) -> [String] {
        let counts = texts.reduce(into: [:]) { $0[$1, default: 0] += 1 }
        var seen = Set<String>()
        return texts.filter { seen.insert($0).inserted }.enumerated()
            .sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }.map(\.element)
    }

    /// The most common entries starting with `prefix` (`starts`), `prefix` itself left out.
    private static func listed(in entries: [Entry], from prefix: String, span: UInt32) -> [String] {
        var scalars = prefix.unicodeScalars
        guard let last = scalars.popLast(), let end = Unicode.Scalar(last.value + span) else { return [] }
        scalars.append(end)
        let lower = start(of: prefix, in: entries), upper = start(of: String(scalars), in: entries)
        return entries[lower..<upper].filter { $0.word != prefix }
            .sorted { ($0.rank, $0.word.count, $0.word) < ($1.rank, $1.word.count, $1.word) }
            .prefix(limit).map(\.word)
    }

    /// The first entry not before `word`.
    private static func start(of word: String, in entries: [Entry]) -> Int {
        var low = 0, high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].word < word { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
