/// Romaji → hiragana, following the conventions of the macOS and Microsoft
/// Japanese input methods (nn/n' → ん, doubled consonants → っ, x/l small kana,
/// - → ー). Letters that can't become kana are kept and counted: like stray jamo
/// for Hangul, they are the strongest sign the user wasn't typing Japanese.
public enum RomajiComposer {
    public struct Result: Equatable, Sendable {
        /// Kana with any unconvertible letters left in place (こんにc while typing).
        public let text: String
        /// Letters in the middle or (when finished) at the end that never became kana.
        public let strayLetters: Int
        /// Letters at the end still waiting to become kana ("k", "ky", "n"); only when partial.
        public let pending: String
        /// Number of kana produced.
        public let kanaCount: Int

        public var isClean: Bool { strayLetters == 0 && pending.isEmpty }
    }

    /// - Parameter partial: the word is still being typed, so a trailing "k" or "n"
    ///   is waiting for its vowel rather than stray.
    public static func compose(_ keys: String, partial: Bool = false) -> Result {
        let chars = Array(keys.lowercased())
        var out = ""
        var stray = 0
        var kana = 0
        var pending = ""
        var i = 0

        func emit(_ s: String) { out += s; kana += s.count }

        while i < chars.count {
            let c = chars[i]
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil

            // Digits are full-width, and so is the punctuation inside a number (０３－１２３４, ３．５).
            if let full = fullWidthDigits[c] { emit(full); i += 1; continue }
            if i > 0, chars[i - 1].isASCII, chars[i - 1].isNumber, let full = numberPunctuation[c] {
                emit(full); i += 1; continue
            }
            if c == "n" {
                if let next {
                    if next == "'" { emit("ん"); i += 2; continue }
                    if next == "n" {
                        // "nni" → んに, "nn" → ん
                        let after: Character? = i + 2 < chars.count ? chars[i + 2] : nil
                        emit("ん")
                        i += (after.map { vowels.contains($0) || $0 == "y" } ?? false) ? 1 : 2
                        continue
                    }
                    if !vowels.contains(next) && next != "y" { emit("ん"); i += 1; continue }
                } else {
                    if partial { pending = "n" } else { emit("ん") }
                    i += 1
                    continue
                }
            } else if let next, next == c, consonants.contains(c) {
                emit("っ"); i += 1; continue
            } else if c == "t", next == "c", i + 2 < chars.count, chars[i + 2] == "h" {
                emit("っ"); i += 1; continue // matcha: "tch" → っch
            }

            var matched = false
            for length in stride(from: min(4, chars.count - i), through: 1, by: -1) {
                if let k = table[String(chars[i..<i + length])] {
                    emit(k)
                    i += length
                    matched = true
                    break
                }
            }
            if matched { continue }

            let rest = String(chars[i...])
            if partial, prefixes.contains(rest) {
                pending = rest
                break
            }
            out.append(c)
            stray += 1
            i += 1
        }
        return Result(text: out + pending, strayLetters: stray, pending: pending, kanaCount: kana)
    }

    /// Hiragana → katakana (for F7-style katakana output and loanwords).
    public static func katakana(_ hiragana: String) -> String {
        String(String.UnicodeScalarView(hiragana.unicodeScalars.map { s in
            (0x3041...0x3096).contains(s.value) ? Unicode.Scalar(s.value + 0x60)! : s
        }))
    }

    /// A spelling that composes back to `kana` (し → "si", ん → "n'", っ → "ltu"), or nil if
    /// some character has none. For keys rewritten after Delete took off a whole kana.
    public static func romaji(_ kana: String) -> String? {
        var out = ""
        for ch in kana {
            guard let r = spelling[ch] else { return nil }
            out += r
        }
        return out
    }

    /// The shortest table entry for each single kana (ties: alphabetical); ん as "n'" so a
    /// vowel typed after it can't take it over (n'a is んあ, nna would be んな).
    static let spelling: [Character: String] = {
        var s: [Character: String] = ["ん": "n'"]
        for (key, value) in table where value.count == 1 {
            let ch = value.first!
            if let old = s[ch], old.count < key.count || (old.count == key.count && old < key) { continue }
            if ch != "ん" { s[ch] = key }
        }
        return s
    }()

    /// Symbols as Japanese IMEs type them by default: full-width, with
    /// [ ] / ~ - as 「」・〜ー. Not ' (it ends ん in kan'i), and digits and spaces stay half-width.
    public static let symbols: [Character: String] = [
        ",": "、", ".": "。", "?": "？", "!": "！", "-": "ー", "/": "・", "[": "「", "]": "」", "~": "〜",
        "_": "＿", "(": "（", ")": "）", ":": "：", ";": "；", "\"": "”", "@": "＠", "#": "＃", "$": "＄",
        "%": "％", "&": "＆", "*": "＊", "+": "＋", "=": "＝", "<": "＜", ">": "＞", "{": "｛", "}": "｝",
        "|": "｜", "^": "＾", "`": "｀", "\\": "＼",
    ]

    /// What the symbols become, except ー, which is part of a word (らーめん) rather than punctuation.
    public static let punctuation: Set<Character> = Set(symbols.values.compactMap(\.first)).subtracting(["ー"])

    /// 0–9 as ０–９, for a Japanese phrase with a number in it.
    static let fullWidthDigits: [Character: String] = Dictionary(uniqueKeysWithValues: (0...9).map {
        (Character(String($0)), String(UnicodeScalar(0xFF10 + UInt32($0))!))
    })
    /// After a digit, - . , / belong to the number (addresses, phone numbers, dates), not ー。、・.
    static let numberPunctuation: [Character: String] = ["-": "－", ".": "．", ",": "，", "/": "／"]

    static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]
    static let consonants: Set<Character> = Set("bcdfghjklmpqrstvwxyz")

    static let table: [String: String] = {
        var t: [String: String] = [
            "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",
            "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
            "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
            "sa": "さ", "si": "し", "su": "す", "se": "せ", "so": "そ",
            "za": "ざ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
            "ta": "た", "ti": "ち", "tu": "つ", "te": "て", "to": "と",
            "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
            "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
            "ha": "は", "hi": "ひ", "hu": "ふ", "he": "へ", "ho": "ほ",
            "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
            "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
            "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
            "ya": "や", "yi": "い", "yu": "ゆ", "ye": "いぇ", "yo": "よ",
            "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
            "wa": "わ", "wi": "うぃ", "wu": "う", "we": "うぇ", "wo": "を",
            "fa": "ふぁ", "fi": "ふぃ", "fu": "ふ", "fe": "ふぇ", "fo": "ふぉ",
            "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",
            "qa": "くぁ", "qi": "くぃ", "qu": "く", "qe": "くぇ", "qo": "くぉ",
            "shi": "し", "chi": "ち", "tsu": "つ", "ji": "じ",
            "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
            "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
            "ja": "じゃ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
            "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",
            "tha": "てゃ", "thi": "てぃ", "thu": "てゅ", "the": "てぇ", "tho": "てょ",
            "dha": "でゃ", "dhi": "でぃ", "dhu": "でゅ", "dhe": "でぇ", "dho": "でょ",
            "twu": "とぅ", "dwu": "どぅ",
            "wha": "うぁ", "whi": "うぃ", "whu": "う", "whe": "うぇ", "who": "うぉ",
            "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
            "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
            "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ", "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ",
            "xtu": "っ", "ltu": "っ", "xtsu": "っ", "ltsu": "っ", "xwa": "ゎ", "lwa": "ゎ",
            // As macOS and MS-IME accept them (not ca/ci/cu: they made English words read as romaji).
            "kwa": "くぁ", "gwa": "ぐぁ", "xn": "ん",
        ]
        for (symbol, full) in symbols { t[String(symbol)] = full }
        // Contracted sounds: きゃ, ぎゅ, みょ…
        let rows: [(String, String)] = [("k", "き"), ("g", "ぎ"), ("s", "し"), ("z", "じ"), ("t", "ち"), ("d", "ぢ"),
                                        ("n", "に"), ("h", "ひ"), ("b", "び"), ("p", "ぴ"), ("m", "み"), ("r", "り"),
                                        ("c", "ち"), ("j", "じ"), ("f", "ふ")]
        for (consonant, i) in rows {
            t[consonant + "ya"] = i + "ゃ"
            t[consonant + "yi"] = i + "ぃ"
            t[consonant + "yu"] = i + "ゅ"
            t[consonant + "ye"] = i + "ぇ"
            t[consonant + "yo"] = i + "ょ"
        }
        return t
    }()

    /// Every proper prefix of a table entry: what a word may end in while still being typed.
    static let prefixes: Set<String> = {
        var p: Set<String> = ["n"]
        for key in table.keys where key.count > 1 {
            for length in 1..<key.count { p.insert(String(key.prefix(length))) }
        }
        return p
    }()
}
