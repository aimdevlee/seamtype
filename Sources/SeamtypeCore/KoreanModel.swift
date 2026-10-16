import Foundation

/// Syllable-unigram model for Korean: enough to tell "안녕하세요" from the accidental
/// Hangul that English produces on a 2-set layout (e.g. "the" → "솓").
public struct KoreanModel: Sendable {
    public struct Score: Sendable {
        /// Average log-probability per keystroke.
        public let averageLogProbability: Double
        public let composition: HangulComposer.Result
    }

    private let tiers: [Character: Double]
    /// Words seen in Korean sentences (Data/korean_words.txt, Tatoeba): 나는, 무슨, 내가…
    private let words: Set<String>

    static let tier1LogP = -5.0
    static let tier2LogP = -6.5
    static let tier3LogP = -8.0
    static let unknownSyllableLogP = -11.0
    static let strayJamoLogP = -13.0
    /// Typing the first consonant of the next syllable is normal mid-word.
    static let pendingConsonantLogP = -3.5
    /// ㅋㅋ, ㅎㅎ, ㅠㅠ and friends.
    static let chatJamoLogP = -4.0
    static let chatJamo: Set<Character> = Set("ㅋㅎㅠㅜㄷㅇㄱㅅㅂㄴ")

    /// Where syllable probabilities come from.
    public enum Source: String, Sendable {
        /// The hand-curated frequency tiers in KoreanSyllables.swift.
        case tiers
        /// Counts from Korean sentences (Data/korean_syllables.txt, Tatoeba, CC-BY 2.0 FR).
        case corpus
        /// Whichever of the two rates a syllable higher.
        case max
    }

    public init(source: Source = .max) {
        var map: [Character: Double] = [:]
        if source != .corpus {
            for (syllables, logP) in [(KoreanSyllables.tier3, Self.tier3LogP),
                                      (KoreanSyllables.tier2, Self.tier2LogP),
                                      (KoreanSyllables.tier1, Self.tier1LogP)] {
                for s in syllables where ("가"..."힣").contains(s) {
                    map[s] = logP // later (more frequent) tiers overwrite earlier ones
                }
            }
        }
        if source != .tiers, let counts = Self.corpusCounts() {
            let total = Double(counts.values.reduce(0, +))
            let smoothing = 0.5, possible = 11172.0
            for (s, n) in counts {
                let logP = log((Double(n) + smoothing) / (total + smoothing * possible))
                map[s] = Swift.max(map[s] ?? -.infinity, logP)
            }
        }
        tiers = map
        words = Self.corpusWords
    }

    /// A word that occurs in real Korean text (the composed Hangul, not the keys).
    public func isKnownWord(_ hangul: String) -> Bool { words.contains(hangul) }

    /// A word in the wider vocabulary (loanwords like 월드, 서버), for English + Korean splits.
    public func isVocabularyWord(_ hangul: String) -> Bool {
        words.contains(hangul) || Self.vocabulary.contains(hangul)
    }

    private static let vocabulary: Set<String> = {
        guard let url = Resources.koreanVocabulary, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }()

    private static let corpusWords: Set<String> = {
        guard let url = Resources.koreanWords, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(whereSeparator: \.isNewline).compactMap { $0.split(separator: "\t").first.map(String.init) })
    }()

    private static func corpusCounts() -> [Character: Int]? {
        guard let url = Resources.koreanSyllables, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var counts: [Character: Int] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t")
            if parts.count == 2, let s = parts[0].first, let n = Int(parts[1]) { counts[s] = n }
        }
        return counts
    }

    public func syllableLogProbability(_ syllable: Character) -> Double {
        tiers[syllable] ?? Self.unknownSyllableLogP
    }

    /// A syllable seen at all, in the tiers or the corpus, however rarely (삐, 쪄, 뾰 are; 뗘, 쎠,
    /// 쓔 aren't). Rarer than `unknownSyllableLogP` still means someone typed it.
    public func knowsSyllable(_ syllable: Character) -> Bool { tiers[syllable] != nil }

    /// - Parameter partial: the token is still being typed, so a trailing lone
    ///   consonant is expected rather than penalized.
    public func score(keys: String, partial: Bool = false) -> Score? {
        guard let composition = HangulComposer.compose(keys: keys), !keys.isEmpty else { return nil }
        let units = composition.units
        let allChat = units.count >= 2 && units.allSatisfy {
            if case .jamo(let j) = $0 { return Self.chatJamo.contains(j) }
            return false
        }
        var total = 0.0
        for (i, unit) in units.enumerated() {
            switch unit {
            case .syllable(let s):
                total += syllableLogProbability(s)
            case .jamo(let j):
                if allChat {
                    total += Self.chatJamoLogP
                } else if partial && i == units.count - 1 && Jamo.isConsonant(j) {
                    total += Self.pendingConsonantLogP
                } else {
                    total += Self.strayJamoLogP
                }
            }
        }
        return Score(averageLogProbability: total / Double(keys.count), composition: composition)
    }
}
