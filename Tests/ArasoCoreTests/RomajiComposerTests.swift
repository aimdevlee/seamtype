import Testing
@testable import ArasoCore

@Suite struct RomajiComposerTests {
    @Test(arguments: [
        ("konnnichiha", "こんにちは"), ("arigatou", "ありがとう"), ("kitte", "きって"), ("ra-men", "らーめん"),
        ("shinbun", "しんぶん"), ("kan'i", "かんい"), ("tenki", "てんき"), ("nihongo", "にほんご"),
        ("kyou", "きょう"), ("gakkou", "がっこう"), ("matcha", "まっちゃ"), ("shashin", "しゃしん"),
        ("tsukue", "つくえ"), ("fujisan", "ふじさん"), ("jouzu", "じょうず"), ("onnna", "おんな"),
        ("rennai", "れんあい"), ("ren'ai", "れんあい"), ("konnichiha", "こんいちは"), ("minnna", "みんな"), ("xtu", "っ"), ("dhisuku", "でぃすく"), ("wo", "を"),
        ("benkyou", "べんきょう"), ("hon", "ほん"), ("sushi", "すし"),
    ])
    func composes(romaji: String, expected: String) {
        let r = RomajiComposer.compose(romaji)
        #expect(r.text == expected)
        #expect(r.isClean)
    }

    /// Delete rewrites the keys from these spellings, so each must compose back to its kana,
    /// also with a vowel typed after it (ん before あ).
    @Test func respellingsComposeBack() {
        for (kana, romaji) in RomajiComposer.spelling {
            #expect(RomajiComposer.compose(romaji, partial: true).text == String(kana), "\(kana) \(romaji)")
            #expect(RomajiComposer.compose(romaji + "a").text == String(kana) + "あ", "\(kana) \(romaji)a")
        }
    }

    @Test func pendingWhileTyping() {
        let r = RomajiComposer.compose("konnnic", partial: true)
        #expect(r.text == "こんにc")
        #expect(r.pending == "c")
        #expect(r.strayLetters == 0)
        #expect(RomajiComposer.compose("hon", partial: true).text == "ほn")
        // nn is ん at once; a third n waits for its vowel (れんな is rennna).
        #expect(RomajiComposer.compose("renn", partial: true).text == "れん")
        #expect(RomajiComposer.compose("renn", partial: true).pending.isEmpty)
        #expect(RomajiComposer.compose("rennn", partial: true).pending == "n")
    }

    /// Letters that don't become kana stay as typed: a capital P waiting for its vowel is P.
    @Test func lettersLeftOverKeepTheirCase() {
        #expect(RomajiComposer.compose("P", partial: true).text == "P")
        #expect(RomajiComposer.compose("P", partial: true).pending == "P")
        #expect(RomajiComposer.compose("KonnniC", partial: true).text == "こんにC")
        #expect(RomajiComposer.compose("HoN", partial: true).text == "ほN")
        #expect(RomajiComposer.compose("Pdf").text == "Pdf")
        #expect(RomajiComposer.compose("Konnnichiha").text == "こんにちは")
    }

    @Test(arguments: ["strength", "dkssud", "world", "keyboard", "gksrmf"])
    func nonJapaneseLeavesStrayLetters(word: String) {
        #expect(RomajiComposer.compose(word).strayLetters > 0)
    }

    /// Like real Japanese IMEs, some English converts cleanly (hello → へっぉ);
    /// telling these apart is the detector's job, not the composer's.
    @Test func someEnglishConvertsCleanly() {
        #expect(RomajiComposer.compose("hello").text == "へっぉ")
    }

    @Test func katakana() {
        #expect(RomajiComposer.katakana("こんぴゅーたー") == "コンピューター")
    }
}
