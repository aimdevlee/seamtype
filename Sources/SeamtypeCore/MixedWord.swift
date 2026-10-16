/// An English word with a Korean particle or ending typed straight after it,
/// e.g. `githubdp` → `github에`, `APIfmf` → `API를`, `commitgotj` → `commit해서`.
public struct MixedWord: Equatable, Sendable {
    public let english: String
    public let koreanKeys: String
    public let korean: String

    public var text: String { english + korean }

    /// Particles and endings that commonly attach directly to a (loan)word.
    static let suffixes: Set<String> = Set("""
    에 에서 에게 에는 에서는 에도 에서도 의 을 를 은 는 이 가 도 로 으로 와 과 랑 이랑 하고 한테 까지 부터 만 보다
    처럼 이나 나 이야 야 이에요 예요 이다 입니다 인데 이라 이라고 라고 으로는 로는 으로도 로도 이고 이지 이랑은
    했어 했다 했어요 했는데 했고 했지 했음 해서 해야 하는 하면 하고 하기 하게 하다 해 해요 합니다 할 한 함 하자 해줘 해봐
    됐어 됐다 된 되는 되면 돼 돼요 됩니다 같은 같아 적 적인 적으로 스럽게 같이 들 들이 들을 들은 에요 이요 를요 을요
    같은건 같은거 같은게 같은걸 같은데 같다 같네 같아서 같은지 같고 같아요 인가 인지 인데요 인건 인게 인거
    이라는 라는 이란 에선 으론 로서 으로서
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    /// Particles that follow a single letter (x에, n이, a를, X축의 X): case particles only, not
    /// endings like 해/한, so short English (ago) doesn't split.
    static let singleLetterParticles: Set<String> = Set("""
    에 에서 에게 에는 에서는 에도 의 을 를 은 는 이 가 도 로 으로 와 과 랑 이랑 하고 한테 까지 부터 만 보다
    처럼 이나 나 이라 이라고 라고 이랑은 으로는 로는 같은 같이
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    /// A single letter and a particle: `xdp` → `x에`, `Xfmf` → `X를`. One key on its own can't
    /// make a Hangul syllable before another consonant, so the keys never read as Korean.
    public static func splitSingleLetter(_ keys: String) -> MixedWord? {
        guard keys.count >= 2, let first = keys.first, first.isASCII, first.isLetter else { return nil }
        let suffixKeys = String(keys.dropFirst())
        guard suffixKeys.first.map(DubeolsikLayout.startsSyllable) == true,
              let composed = HangulComposer.compose(keys: suffixKeys), composed.strayJamo.isEmpty,
              singleLetterParticles.contains(composed.text) else { return nil }
        // 도 and 나 are the keys eh and sk, common English endings (heh, meh, yeh, tsk): after a
        // lowercase letter they stay English. A capital (X도) was typed on purpose.
        if first.isLowercase, ["도", "나"].contains(composed.text) { return nil }
        return MixedWord(english: String(first), koreanKeys: suffixKeys, korean: composed.text)
    }

    /// Splits off the longest Korean particle/ending at the end of `keys`.
    /// Only the shape is checked here; whether the front really is English is
    /// up to the caller (see `SplittingEngine`).
    public static func split(_ keys: String) -> MixedWord? {
        let chars = Array(keys)
        // Front needs at least 2 letters; try the longest suffix first.
        guard chars.count >= 3 else { return nil }
        for start in 2..<chars.count {
            let suffixKeys = String(chars[start...])
            guard suffixKeys.first.map(DubeolsikLayout.startsSyllable) == true,
                  let composed = HangulComposer.compose(keys: suffixKeys),
                  composed.strayJamo.isEmpty,
                  suffixes.contains(composed.text) else { continue }
            return MixedWord(english: String(chars[..<start]), koreanKeys: suffixKeys, korean: composed.text)
        }
        return nil
    }
}

extension DubeolsikLayout {
    /// A Korean syllable has to start with a consonant key.
    static func startsSyllable(_ key: Character) -> Bool {
        jamo(for: key).map(Jamo.isConsonant) ?? false
    }
}

/// Decides `mixed` for English and Korean typed as one token: English + particle (github에),
/// a single letter + particle (x에), English + Korean word (hello월드), and with Japanese on
/// English + Japanese particle (githubで). Never when the whole token is a known English word or
/// reads as ordinary Korean (every syllable is one people actually use).
public final class SplittingEngine: DecisionEngine, @unchecked Sendable {
    public let base: DecisionEngine
    public let english: EnglishModel
    public let korean: KoreanModel
    /// English word + Korean word (hello월드) only when the whole token spells less like
    /// English than this; stricter still when the Korean half isn't in the word lists.
    public var mixedWordSpellingCeiling = -2.7
    public var unknownWordSpellingCeiling = -3.2

    /// How sure a split is: above Strict (`AppPolicy.strictThreshold`), since each rule already
    /// asks for an English front it can stand on, so github에 splits in a terminal too.
    public static let confidence = 0.98

    /// With Japanese on: English word + Japanese particle (githubで), decided the same way.
    public let japanese: JapaneseSegmenter?

    /// Scores English word + particle against the whole token.
    public let particles: ParticleSplitter

    public init(base: DecisionEngine, english: EnglishModel, korean: KoreanModel = KoreanModel(),
                japanese: JapaneseSegmenter? = nil) {
        self.base = base
        self.english = english
        self.korean = korean
        self.japanese = japanese
        particles = ParticleSplitter(english: english, korean: korean, japanese: japanese?.japanese)
    }

    public func decide(_ keys: String, context: DecisionContext) -> Decision {
        // English word + particle, Korean (github에) or with Japanese on Japanese (githubで),
        // when that reading beats the whole token in one language. Before English + Korean
        // word: beautywo is beauty + を, not beau + 쇼재.
        switch particles.split(keys, japaneseOn: japanese != nil) {
        case .korean(let mixed)?:
            return Decision(language: .mixed, confidence: Self.confidence, output: mixed.text,
                            explanation: "split \(mixed.english)+\(mixed.korean)")
        case .japanese(let word, let particle)?:
            return Decision(language: .japanese, confidence: Self.confidence, output: word + particle,
                            explanation: "split \(word)+\(particle)")
        case nil: break
        }
        if let mixed = MixedWord.splitSingleLetter(keys), !english.isKnownWord(keys), !readsAsKorean(keys) {
            return Decision(language: .mixed, confidence: Self.confidence, output: mixed.text,
                            explanation: "split \(mixed.english)+\(mixed.korean)")
        }
        if let mixed = englishThenKoreanWord(keys) {
            return Decision(language: .mixed, confidence: Self.confidence, output: mixed.text,
                            explanation: "split \(mixed.english)+\(mixed.korean)")
        }
        return base.decide(keys, context: context)
    }

    /// UI, AI, OS, API: capitals typed on purpose, with at least one that has no shifted
    /// jamo (so it can't be ㅃㅉㄸㄲㅆㅒㅖ). Short ones count too (UI같은건).
    static func isAcronym(_ front: String) -> Bool {
        (2...6).contains(front.count) && front.allSatisfy { $0.isUppercase }
            && front.contains { !DubeolsikLayout.isKoreanShiftKey($0) }
    }

    /// Slack, TextEdit, VSCode, GitHub: a name typed with its capitals, so English even when
    /// it isn't in the word list. Starts with a capital, has lowercase too, and has either a
    /// capital with no shifted jamo or another capital inside (PascalCase). Korean typed with
    /// shift (TkdRjvnf, 쌍꺼풀) also passes the second test; `readsAsKorean` still stops it.
    static func isCapitalizedName(_ front: String) -> Bool {
        guard front.count >= 3, front.first?.isUppercase == true, front.contains(where: \.isLowercase) else { return false }
        if hasEnglishOnlyCapital(front) { return true }
        guard front.dropFirst().contains(where: \.isUppercase) else { return false }
        // Every capital a shifted jamo and the keys spelling whole Hangul is Korean typed with shift,
        // even with a typo making an odd syllable (RoRmtgkgfu, 깨끗핳려), not a name (TextEdit).
        return HangulComposer.compose(keys: front).map { !$0.strayJamo.isEmpty } ?? true
    }

    /// An English word with a whole Korean word typed straight after it, no space:
    /// `hellodnjfem` → `hello월드`, `designvhsxm` → `design폰트`. The front has to be a known
    /// English word (or a name typed with capitals) and the back at least two syllables:
    /// a known Korean word (optionally with a particle), or, when the whole token spells
    /// nothing like English, any Hangul made of syllables people use. Prefers the longest
    /// English front. Names that spell like English stay whole (cartman isn't car스무).
    func englishThenKoreanWord(_ keys: String) -> MixedWord? {
        let chars = Array(keys)
        guard chars.count >= 5, !english.isKnownWord(keys) else { return nil }
        let spelling = english.averageLogProbability(keys)
        // Clean romaji (hasansowo, はさんそを) is Japanese, not English + Hangul.
        guard spelling < mixedWordSpellingCeiling, !RomajiComposer.compose(keys).isClean else { return nil }
        // Capitals count only when one has no Korean meaning (ThkT is 쐈, not a name). Judged on
        // the whole token: the front alone has no lowercase to show a lingering Shift (TMfkrh is
        // 쓰라고, not TM라고). Keys that read as Korean throughout are Korean unless such a capital
        // says otherwise.
        let englishOnlyCapital = Self.hasEnglishOnlyCapital(keys)
        guard englishOnlyCapital || !readsAsKorean(keys) else { return nil }
        for start in stride(from: chars.count - 2, through: 2, by: -1) {
            let front = String(chars[..<start]), back = String(chars[start...])
            guard back.first.map(DubeolsikLayout.startsSyllable) == true,
                  let composed = HangulComposer.compose(keys: back), composed.strayJamo.isEmpty,
                  composed.syllables.count >= 2 else { continue }
            let knownKorean = isKoreanWordOrWordWithParticle(composed.text)
            guard knownKorean
                    || (spelling < unknownWordSpellingCeiling
                        && composed.syllables.allSatisfy { korean.syllableLogProbability($0) > KoreanModel.unknownSyllableLogP })
            else { continue }
            // An acronym a lingering Shift could explain (EU as ㄸ+ㅕ) counts when its own keys spell
            // a syllable no list or corpus has (뗘) and a known Korean word follows. Korean typed
            // fast keeps its rare syllables (삐졌어 as QLwuTdj: 삐 is rare, but seen) and 쓰정책
            // (TMwjdcor) reads as Korean outright; both stay Korean. Only the front is judged: the
            // word after may well hold a rare syllable (또공룡이 as EHrhdfyddl).
            let acronym = Self.isAcronym(front)
            guard (englishOnlyCapital && (acronym || Self.isCapitalizedName(front)))
                    || (acronym && knownKorean && !spellsSeenKorean(front))
                    || (front.count >= 3 && english.isKnownWord(front))
            else { continue }
            return MixedWord(english: front, koreanKeys: back, korean: composed.text)
        }
        return nil
    }

    private func isKoreanWordOrWordWithParticle(_ hangul: String) -> Bool {
        if korean.isVocabularyWord(hangul) { return true }
        let chars = Array(hangul)
        return (1..<chars.count).contains { cut in
            cut >= 2 && korean.isVocabularyWord(String(chars[..<cut])) && MixedWord.suffixes.contains(String(chars[cut...]))
        }
    }

    /// A capital no lingering Shift explains (RNl, 꿀 typed fast, isn't a name).
    static func hasEnglishOnlyCapital(_ front: String) -> Bool {
        DubeolsikLayout.hasEnglishOnlyCapital(front)
    }

    /// Whole Hangul of syllables seen in the corpus or a word list, however rarely (삐, not 뗘).
    private func spellsSeenKorean(_ keys: String) -> Bool {
        guard let composed = HangulComposer.compose(keys: keys), composed.strayJamo.isEmpty else { return false }
        return composed.syllables.allSatisfy(korean.knowsSyllable)
    }

    private func readsAsKorean(_ keys: String) -> Bool {
        guard let composed = HangulComposer.compose(keys: keys), composed.strayJamo.isEmpty else { return false }
        return composed.syllables.allSatisfy { korean.syllableLogProbability($0) > KoreanModel.unknownSyllableLogP }
    }
}
