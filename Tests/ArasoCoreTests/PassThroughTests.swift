import Foundation
import Testing
@testable import ArasoCore

/// Safari's address bar is known a key late: the word begun goes in as its keys.
@MainActor @Suite struct PassThroughTests {
    @Test func aWordShownAsJamoGoesInAsTyped() {
        let session = CapsLockTests.freshSession(), field = FakeTextField()
        _ = session.handle(.letter("w"), client: field)
        #expect(field.text == "ㅈ")
        session.passThrough(client: field)
        #expect(field.text == "w")
        #expect(field.marked.location == NSNotFound)
    }
}

/// In the address bar a search composes as anywhere; an address goes in as typed.
@MainActor @Suite struct AddressBarTests {
    private func type(_ keys: String, _ session: InputSession, _ field: FakeTextField) {
        for ch in keys {
            let key: InputSession.Key = ch == " " ? .printable(" ") : .letter(ch)
            if !session.handleAddressBar(key, client: field) { field.insertText(String(ch), replacing: nil) }
        }
    }

    @Test func anAddressGoesInAsTyped() {
        let session = CapsLockTests.freshSession(), field = FakeTextField()
        type("ppomppu", session, field)
        #expect(field.text == "ppomppu")
        #expect(field.marked.location == NSNotFound)
    }

    @Test func aSearchReadsKorean() {
        let session = CapsLockTests.freshSession(), field = FakeTextField()
        type("dkssudgktpdy ", session, field)
        #expect(field.text == "안녕하세요 ")
    }

    @Test func anAddressAfterASearchWordStaysEnglish() {
        let session = CapsLockTests.freshSession(), field = FakeTextField()
        type("aktwlq google", session, field)
        #expect(field.text == "맛집 google", "\(field.text)")
    }
}
