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
