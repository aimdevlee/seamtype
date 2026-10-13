import Foundation

/// The latest release as GitHub's API describes it
/// (`api.github.com/repos/aimdevlee/seamtype/releases/latest`): its version and the installer.
public struct Release: Equatable, Sendable {
    public var version: String
    public var package: URL
    public var page: URL?

    public init(version: String, package: URL, page: URL? = nil) {
        self.version = version
        self.package = package
        self.page = page
    }

    /// Nil when the answer has no tag or no `Seamtype.pkg` asset.
    public init?(gitHubJSON data: Data) {
        struct Answer: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL?
            let assets: [Asset]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data),
              let package = answer.assets.first(where: { $0.name == "Seamtype.pkg" }) else { return nil }
        version = answer.tag_name.hasPrefix("v") ? String(answer.tag_name.dropFirst()) : answer.tag_name
        self.package = package.browser_download_url
        page = answer.html_url
    }

    /// "0.1.10" is newer than "0.1.9"; a missing part counts as 0 ("0.2" == "0.2.0").
    public static func isNewer(_ version: String, than current: String) -> Bool {
        func parts(_ v: String) -> [Int] { v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 } }
        let a = parts(version), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
