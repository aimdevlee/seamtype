import Testing
@testable import ArasoCore

@Suite struct ShortFrontTests {
    @Test func shortFrontIsAReadingNotADecision() {
        #expect(splitting.decide("ipwnth", context: DecisionContext()).output == "ipwnth")
        #expect(splitting.render("ipwnth", as: .mixed) == "ip주소")
        let splits = splitting.render("ipwnth", as: .mixed) != "ipwnth"
        #expect(Language.english.next(for: "ipwnth", splits: splits) == .mixed)
        #expect(splitting.render("dkssud", as: .mixed) == "dkssud")
    }
}

@Suite struct ShortFrontLearningTests {
    @Test func learnedShortFrontCommitsSplit() {
        let dict = DictionaryEngine(base: splitting, storeURL: nil)
        dict.learn("ipwnth", as: .mixed)
        dict.learn("ipwnth", as: .mixed)
        #expect(dict.decide("ipwnth", context: DecisionContext()).output == "ip주소")
    }
}
