import Foundation
import Testing
@testable import ArasoCore

/// ↓ and ↑ move through the readings a switch key listed, now a vertical list: the next or the one
/// before, stopping at its ends, on the word being typed and on the word just committed.
@MainActor @Suite struct ReadingsArrowTests {
    let field = FakeTextField()
    let session: InputSession

    init() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("araso-arrows-\(UUID().uuidString).json")
        session = InputSession(engine: DictionaryEngine(base: SplittingEngine(base: trilingual, english: trilingual.english,
                                                                              japanese: trilingual.segmenter), storeURL: url))
        session.activate(app: "com.apple.TextEdit")
    }

    func type(_ keys: String) {
        for ch in keys {
            let handled = ch.isLetter ? session.handle(.letter(ch), client: field) : session.handle(.printable(ch), client: field)
            if !handled, ch == " " { field.insertText(" ", replacing: nil) }
        }
    }

    @Test func arrowsMoveThroughTheListWithoutGoingRound() throws {
        type("hello")
        _ = session.handle(.cycle, client: field)
        let first = try #require(session.readings)
        #expect(first.selected == 1)
        let shown = field.text
        #expect(session.handle(.up, client: field))
        #expect(session.readings?.selected == 0)
        #expect(field.text == "hello")
        #expect(session.handle(.up, client: field)) // the top: stays, and the list stays up
        #expect(session.readings?.selected == 0)
        #expect(session.handle(.down, client: field))
        #expect(session.readings?.selected == 1)
        #expect(field.text == shown)
    }

    @Test func arrowsWorkOnTheWordJustCommitted() throws {
        type("hello ")
        _ = session.handle(.cycle, client: field)
        let list = try #require(session.readings)
        let last = list.texts.count - 1
        for _ in 0..<(last - list.selected) { #expect(session.handle(.down, client: field)) }
        #expect(session.readings?.selected == last)
        let there = field.text
        #expect(session.handle(.down, client: field))
        #expect(session.readings?.selected == last)
        #expect(field.text == there)
        #expect(session.takesArrow(.up))
    }

    @Test func withNoListTheyAreTheApps() {
        type("hello ")
        #expect(!session.takesArrow(.down))
        #expect(!session.handle(.down, client: field))
    }
}
