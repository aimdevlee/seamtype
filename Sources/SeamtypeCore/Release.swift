import Foundation

/// The latest release as GitHub's API describes it
/// (`api.github.com/repos/aimdevlee/seamtype/releases/latest`): its version, the installer and
/// what changed.
public struct Release: Equatable, Sendable {
    public var version: String
    public var package: URL
    public var page: URL?
    /// The items of the notes' first section ("## 바뀐 것"), each still Markdown (`**bold**`,
    /// `` `code` ``, links). The rest of the notes is the same install text every time.
    public var notes: [String]

    public init(version: String, package: URL, page: URL? = nil, notes: [String] = []) {
        self.version = version
        self.package = package
        self.page = page
        self.notes = notes
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
            let body: String?
            let assets: [Asset]
        }
        guard let answer = try? JSONDecoder().decode(Answer.self, from: data),
              let package = answer.assets.first(where: { $0.name == "Seamtype.pkg" }) else { return nil }
        version = answer.tag_name.hasPrefix("v") ? String(answer.tag_name.dropFirst()) : answer.tag_name
        self.package = package.browser_download_url
        page = answer.html_url
        notes = Self.changes(in: answer.body ?? "")
    }

    /// A note split into its bold lead and the rest: `**텍스트 대치**: 약어를…` → ("텍스트 대치",
    /// "약어를…"). A note without a bold lead is all title.
    public static func headline(of note: String) -> (title: String, detail: String?) {
        guard note.hasPrefix("**"), let end = note.range(of: "**", range: note.index(note.startIndex, offsetBy: 2)..<note.endIndex)
        else { return (note, nil) }
        let title = String(note[note.index(note.startIndex, offsetBy: 2)..<end.lowerBound])
        let rest = note[end.upperBound...].drop { $0 == ":" || $0 == " " }
        return (title, rest.isEmpty ? nil : String(rest))
    }

    /// The list items of the first `## ` section of release notes; a line that isn't an item
    /// joins the item before it (or stands alone when there is none yet).
    public static func changes(in body: String) -> [String] {
        var items: [String] = []
        var inSection = false
        for raw in body.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## ") {
                if inSection { break }
                inSection = true
            } else if inSection, !line.isEmpty {
                if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    items.append(String(line.dropFirst(2)))
                } else if raw.first == " " || raw.first == "\t", let last = items.indices.last {
                    items[last] += " " + line
                } else {
                    items.append(line)
                }
            }
        }
        return items
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
