import Foundation
import Testing
@testable import SeamtypeCore

/// The update check: GitHub's latest-release answer and version order.
@Suite struct ReleaseTests {
    @Test func readsTheInstallerFromGitHubsAnswer() throws {
        let json = #"""
        { "tag_name": "v0.1.6", "html_url": "https://github.com/aimdevlee/seamtype/releases/tag/v0.1.6",
          "assets": [
            { "name": "Seamtype-0.1.6.pkg", "browser_download_url": "https://example.com/Seamtype-0.1.6.pkg" },
            { "name": "Seamtype.pkg", "browser_download_url": "https://example.com/Seamtype.pkg" },
            { "name": "Seamtype.zip", "browser_download_url": "https://example.com/Seamtype.zip" } ] }
        """#
        let release = try #require(Release(gitHubJSON: Data(json.utf8)))
        #expect(release.version == "0.1.6")
        #expect(release.package.absoluteString == "https://example.com/Seamtype.pkg")
        #expect(release.page?.absoluteString == "https://github.com/aimdevlee/seamtype/releases/tag/v0.1.6")
        // No installer, or not a release at all: nothing to offer.
        #expect(Release(gitHubJSON: Data(#"{ "tag_name": "v0.2", "assets": [] }"#.utf8)) == nil)
        #expect(Release(gitHubJSON: Data(#"{ "message": "Not Found" }"#.utf8)) == nil)
    }

    @Test func readsWhatChangedFromTheNotes() throws {
        let body = """
        ## 바뀐 것

        - **입력 중 지우기**: 가나 한 글자씩(`かんこく` → `かんこ`).
        - **텍스트 대치**: 약어를
          두 줄에 걸쳐 씁니다.

        ## 설치·업데이트

        - 설치 파일을 받아 여세요.
        """
        #expect(Release.changes(in: body) == [
            "**입력 중 지우기**: 가나 한 글자씩(`かんこく` → `かんこ`).",
            "**텍스트 대치**: 약어를 두 줄에 걸쳐 씁니다.",
        ])
        #expect(Release.changes(in: "") == [])
        #expect(Release.changes(in: "## Changes\n\nOne paragraph.\n") == ["One paragraph."])

        let json = #"""
        { "tag_name": "v0.2.0", "body": "## 바뀐 것\r\n\r\n- 하나\r\n- 둘\r\n",
          "assets": [ { "name": "Seamtype.pkg", "browser_download_url": "https://example.com/Seamtype.pkg" } ] }
        """#
        #expect(try #require(Release(gitHubJSON: Data(json.utf8))).notes == ["하나", "둘"])
    }

    /// The draft's notes start from this template; published unfilled, About shows nothing.
    @Test func theNotesTemplateListsNothingYet() throws {
        let template = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(".github/release-notes.md")
        let body = try String(contentsOf: template, encoding: .utf8)
        #expect(body.contains("## 바뀐 것"))
        #expect(Release.changes(in: body) == [])
        #expect(Release.changes(in: body.replacingOccurrences(of: "## 바뀐 것\n", with: "## 바뀐 것\n\n- **새 기능**: 설명\n"))
            == ["**새 기능**: 설명"])
    }

    @Test func splitsANoteIntoTitleAndDetail() {
        #expect(Release.headline(of: "**텍스트 대치**: 약어를 `ㅈㅅ`처럼") == ("텍스트 대치", "약어를 `ㅈㅅ`처럼"))
        #expect(Release.headline(of: "**짧은 것**") == ("짧은 것", nil))
        #expect(Release.headline(of: "그냥 문장입니다.") == ("그냥 문장입니다.", nil))
    }

    @Test func comparesVersionsByNumber() {
        #expect(Release.isNewer("0.1.10", than: "0.1.9"))
        #expect(Release.isNewer("0.2", than: "0.1.9"))
        #expect(Release.isNewer("1.0.0", than: "0.9"))
        #expect(!Release.isNewer("0.1.5", than: "0.1.5"))
        #expect(!Release.isNewer("0.2", than: "0.2.0"))
        #expect(!Release.isNewer("0.1.4", than: "0.1.5"))
    }

    @Test func updateChecksAreOnUnlessTurnedOff() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("seamtype-release-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{ "japanese": true }"#.utf8).write(to: url)
        #expect(Settings.load(from: url).checkForUpdates)
        try Settings(checkForUpdates: false).save(to: url)
        #expect(!Settings.load(from: url).checkForUpdates)
    }
}
