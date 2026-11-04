import Foundation

/// What a Korean word typed with one slip of the fingers could have been (#85): two neighbouring keys
/// swapped (치다가 typed clekkr, read 치다ㅏㄱ), a key pressed twice or missed, Shift too late or too early
/// (했 typed goT … got, 햇), or the key next to the one meant (영어 typed djddj, 엉어). Each slip undone
/// gives keys; those that compose to a word of the lists without stray jamo are the guesses.
///
/// Keys are the English layout's letters, as everywhere; the slips are counted on the keys under them
/// (QWERTY's seats, `LatinLayout.seat(of:)`), so a neighbour is the key next to it on Colemak too. 2-set
/// only: 3-set's keys are other jamo, and its slips other slips.
///
/// The guesses go two ways (`InputSession`): all of them, on a long press of the switch key, for the
/// user to pick one; the first, at the end of the word, only when the keys can't be Korean as typed
/// and nothing comes close (`autoFix`).
public struct SlipGuesser: Sendable {
    public enum Slip: Int, Comparable, Sendable {
        /// A key pressed once too often (치다가ㅏ): the commonest slip, and the safest to undo, so first.
        case extra
        /// Two neighbouring keys the other way round (clekkr for clekrk).
        case swapped
        /// Shift on a key where it changes the jamo, held a key too long or let go too soon (got for goT).
        case shift
        /// A key left out (dlrj for dlrjs).
        case missing
        /// The key next to the one meant (djddj for duddj).
        case neighbor

        public static func < (a: Slip, b: Slip) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Guess: Equatable, Sendable {
        /// The keys the slip undone gives, in the English layout's letters.
        public let keys: String
        public let text: String
        public let slip: Slip
        /// 0: a word of Korean sentences (`KoreanModel.isKnownWord`), 1: of the wider vocabulary,
        /// 2: one the subtitles have only a few times (three syllables or more).
        let tier: Int
        let count: Int
        let score: Double

        /// Better first: the list a word is from, then how common it is (했어요 before 해서요 for
        /// gotdjdy), then the slip, then its syllables.
        func ranks(before other: Guess) -> Bool {
            if tier != other.tier { return tier < other.tier }
            if count != other.count { return count > other.count }
            if slip != other.slip { return slip < other.slip }
            return score > other.score
        }
    }

    /// How many guesses the long press lists.
    public static let limit = 5
    /// Fewer keys than this are left alone: a short word has too many neighbours.
    static let fixableKeys = 4...30
    /// Another guess from the same list this many times less common than the first doesn't stand in
    /// its way (했어요 3,496 against 해서요 284).
    static let clearLead = 10
    /// English letters at least this likely per letter (`EnglishModel.averageLogProbability`) are
    /// left as English could have them: tbody (-3.7), gmail (-3.4), against clekkr's -3.9.
    static let englishLike = -3.8

    let korean: KoreanModel
    let english: EnglishModel

    public init(korean: KoreanModel = KoreanModel(), english: EnglishModel = .shared) {
        self.korean = korean
        self.english = english
    }

    /// Every word one slip away from `keys`, best first, at most `limit`. Not the keys' own reading.
    public func guesses(for keys: String, limit: Int = Self.limit) -> [Guess] {
        guard KoreanLayout.current == .dubeolsik, !keys.isEmpty else { return [] }
        let layout = LatinLayout.current
        let seats = keys.map(layout.seat(of:))
        guard seats.allSatisfy({ $0.isASCII && $0.isLetter }) else { return [] }
        let own = HangulComposer.compose(keys: keys)?.text
        var best: [String: Guess] = [:]
        func consider(_ candidate: [Character], _ slip: Slip) {
            let letters = String(candidate.map(layout.character(onSeat:)))
            guard let composed = HangulComposer.compose(keys: letters), composed.strayJamo.isEmpty,
                  composed.syllables.count >= 2, composed.text != own,
                  let tier = tier(of: composed.text, syllables: composed.syllables.count) else { return }
            let guess = Guess(keys: letters, text: composed.text, slip: slip, tier: tier,
                              count: korean.vocabularyCount(composed.text),
                              score: korean.score(keys: letters)?.averageLogProbability ?? -.infinity)
            if let held = best[guess.text], held.ranks(before: guess) { return }
            best[guess.text] = guess
        }
        for i in seats.indices { // extra
            var c = seats; c.remove(at: i); consider(c, .extra)
        }
        for i in seats.indices.dropLast() where seats[i] != seats[i + 1] { // swapped
            var c = seats; c.swapAt(i, i + 1); consider(c, .swapped)
        }
        for i in seats.indices { // shift
            let toggled = Self.toggleShift(seats[i])
            guard toggled != seats[i], Self.shiftedJamo.contains(Character(seats[i].lowercased())) else { continue }
            var c = seats; c[i] = toggled; consider(c, .shift)
        }
        for i in 0...seats.count { // missing
            for key in Self.insertable { var c = seats; c.insert(key, at: i); consider(c, .missing) }
        }
        for i in seats.indices { // neighbor
            for n in Self.neighbors(of: seats[i]) { var c = seats; c[i] = n; consider(c, .neighbor) }
        }
        return Array(best.values.sorted { $0.ranks(before: $1) }.prefix(limit))
    }

    /// The guess to put in at the end of the word without asking: only for keys that can't be Korean
    /// as typed (stray jamo, or a syllable no word of the lists has: 섩치; a word of syllables only if
    /// Shift on a final is all that is off, 햇어요 for 했어요, not 에요 for 예요), aren't English and don't
    /// end on chat jamo (고마워ㅠ), when the first guess has two syllables or more (three after English or
    /// Japanese, `afterKorean` false) and no other comes close. The
    /// caller still asks the engine (the guess must read as Korean) and the dictionary (keys it
    /// remembers are left alone).
    public func autoFix(_ keys: String, afterKorean: Bool) -> Guess? {
        guard KoreanLayout.current == .dubeolsik, Self.fixableKeys.contains(keys.count),
              keys.allSatisfy(\.isLetter), !english.isKnownWord(keys),
              english.averageLogProbability(keys.lowercased()) < Self.englishLike,
              let composed = HangulComposer.compose(keys: keys) else { return nil }
        if Self.endsInChat(composed) { return nil }
        let broken = !composed.strayJamo.isEmpty || composed.syllables.contains(where: isOdd)
        if !broken, korean.isVocabularyWord(composed.text) || korean.isRareVocabularyWord(composed.text) { return nil }
        let guesses = guesses(for: keys, limit: 2)
        guard let first = guesses.first,
              broken || first.slip == .shift && Self.differsInFinalsOnly(composed.text, first.text),
              first.text.count >= (afterKorean ? 2 : 3) else { return nil }
        if let second = guesses.dropFirst().first, second.tier == first.tier,
           first.count < second.count * Self.clearLead { return nil }
        return first
    }

    /// A syllable no word of the lists has, rare ones included, and not an ending any stem takes on:
    /// ㅂ of ㅂ니다, ㅁ of a noun, ㅆ of the past (나뉩니다, 만듦, 셌다 aren't in the lists as such).
    func isOdd(_ syllable: Character) -> Bool {
        guard !korean.knowsSyllableIncludingRare(syllable) else { return false }
        guard let value = syllable.unicodeScalars.first?.value, (0xAC00...0xD7A3).contains(value) else { return true }
        let final = (value - 0xAC00) % 28
        guard let stem = Self.endingFinals[final], let open = Unicode.Scalar(value - final + stem) else { return true }
        return !korean.knowsSyllableIncludingRare(Character(open))
    }

    /// Finals an ending adds (ㅂ, ㅁ, ㅆ, and ㄻ over ㄹ), and the final the stem has without it.
    private static let endingFinals: [UInt32: UInt32] = [17: 0, 16: 0, 20: 0, 10: 8]

    /// Two words of the same syllables but for their finals (햇어요, 했어요): Shift let go on a final.
    static func differsInFinalsOnly(_ a: String, _ b: String) -> Bool {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        guard x.count == y.count, x != y else { return false }
        return zip(x, y).allSatisfy { p, q in
            guard (0xAC00...0xD7A3).contains(p.value), (0xAC00...0xD7A3).contains(q.value) else { return p == q }
            return (p.value - 0xAC00) / 28 == (q.value - 0xAC00) / 28
        }
    }

    /// Which characters of `guess` differ from `typed`, the keys' own reading: what lies between what
    /// they share at the start and at the end (누ㅜ를 → 누구를: 구). Empty where the guess only drops some.
    public static func changed(from typed: String, to guess: String) -> Range<Int> {
        let a = Array(typed), b = Array(guess)
        let start = zip(a, b).prefix { $0 == $1 }.count
        let end = zip(a.dropFirst(start).reversed(), b.dropFirst(start).reversed()).prefix { $0 == $1 }.count
        return start..<(b.count - end)
    }

    /// The word ends on jamo typed for chat: ㅠ or ㅜ, or two or more of `KoreanModel.chatJamo`
    /// (고마워ㅠ, 좋아ㅋㅋ). A single consonant left over (치다ㅏㄱ) is a slip.
    static func endsInChat(_ composed: HangulComposer.Result) -> Bool {
        let tail = composed.units.reversed().prefix { if case .jamo = $0 { return true } else { return false } }.map(\.character)
        guard !tail.isEmpty, tail.allSatisfy(KoreanModel.chatJamo.contains) else { return false }
        return tail.count >= 2 || tail[0] == "ㅠ" || tail[0] == "ㅜ"
    }

    private func tier(of word: String, syllables: Int) -> Int? {
        if korean.isKnownWord(word) { return 0 }
        if korean.isVocabularyWord(word) { return 1 }
        if syllables >= 3, korean.isRareVocabularyWord(word) { return 2 }
        return nil
    }

    /// QWERTY's letter keys, as `DubeolsikLayout` sits on them.
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    /// Keys whose shifted jamo is another (ㅃㅉㄸㄲㅆㅒㅖ).
    private static let shiftedJamo: Set<Character> = Set("qwertop")
    private static let insertable: [Character] = Array(rows.joined()) + Array("QWERTOP")

    private static func toggleShift(_ seat: Character) -> Character {
        Character(seat.isUppercase ? seat.lowercased() : seat.uppercased())
    }

    /// The keys around `seat` on a staggered keyboard: either side, and the two above and below that
    /// touch it. A shifted key's neighbours keep the Shift where it changes their jamo.
    static func neighbors(of seat: Character) -> [Character] {
        let lowered = Character(seat.lowercased())
        guard let row = rows.firstIndex(where: { $0.contains(lowered) }) else { return [] }
        let keys = rows.map(Array.init)
        let i = keys[row].firstIndex(of: lowered)!
        var around: [Character] = []
        func add(_ r: Int, _ c: Int) { if keys.indices.contains(r), keys[r].indices.contains(c) { around.append(keys[r][c]) } }
        add(row, i - 1); add(row, i + 1)
        add(row - 1, i); add(row - 1, i + 1)
        add(row + 1, i - 1); add(row + 1, i)
        guard seat.isUppercase else { return around }
        return around.map { shiftedJamo.contains($0) ? Character($0.uppercased()) : $0 }
    }
}
