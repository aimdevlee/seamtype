import AppKit
import SeamtypeCore

/// Updates: asks GitHub for the latest release's version (nothing else is sent) once a day from
/// the input method, each time the settings window opens, and on Check Now. A newer one shows in
/// the input menu and in About, with what changed in it (the release notes' first section), whose Install button downloads `Seamtype.pkg`, checks that it is
/// signed with Seamtype's Developer ID and notarized, and opens it in Installer (macOS asks for
/// the password there). Nothing installs on its own: the user picks the moment.
///
/// The input method and the settings window are separate processes; what the last check found is
/// shared through the bundle's user defaults.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    enum State: Equatable {
        case idle, checking, upToDate, downloading, failed(String)
    }

    @Published private(set) var state = State.idle
    /// A release newer than this copy, from the last check by either process.
    @Published private(set) var available: Release?

    private static let gitHub = URL(string: "https://api.github.com/repos/aimdevlee/seamtype/releases/latest")!
    /// GitHub's latest release, or, for trying an update before it is published (drafts aren't
    /// visible without a login), a file in the same format whose `browser_download_url` may be a
    /// file URL: `defaults write com.aimdevlee.inputmethod.Seamtype updateFeed file:///…/latest.json`.
    /// The installer still has to pass the signature check.
    private static var latest: URL {
        UserDefaults.standard.string(forKey: "updateFeed").flatMap(URL.init(string:)) ?? gitHub
    }
    private static let teamID = "2UZ65T3U82"
    private static let interval: TimeInterval = 24 * 60 * 60
    private enum Key {
        static let checked = "updateLastCheck", version = "updateVersion", package = "updatePackage", page = "updatePage", notes = "updateNotes"
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private var timer: Timer?

    private init() { available = Self.stored() }

    /// What the last check found, if it is still newer than this copy.
    private static func stored() -> Release? {
        let defaults = UserDefaults.standard
        guard let version = defaults.string(forKey: Key.version),
              let package = defaults.string(forKey: Key.package).flatMap(URL.init(string:)),
              Release.isNewer(version, than: currentVersion) else { return nil }
        return Release(version: version, package: package,
                       page: defaults.string(forKey: Key.page).flatMap(URL.init(string:)),
                       notes: defaults.stringArray(forKey: Key.notes) ?? [])
    }

    /// Reads again what the last check found, which the other process may have written.
    func refresh() { available = Self.stored() }

    /// The input method: a check a minute after it starts, then hourly wake-ups that check only
    /// once a day has passed, while the setting is on.
    func startDailyChecks() {
        timer?.invalidate()
        let tick = { @MainActor in
            guard Runtime.shared.settings.checkForUpdates else { return }
            let last = UserDefaults.standard.object(forKey: Key.checked) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) >= Self.interval { Updater.shared.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { MainActor.assumeIsolated { tick() } }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
    }

    /// Asks GitHub now.
    func check() {
        guard state != .checking, state != .downloading else { return }
        state = .checking
        var request = URLRequest(url: Self.latest, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Seamtype/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            // A file (the updateFeed override) has no HTTP status.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            let release = data.flatMap(Release.init(gitHubJSON:))
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    Updater.shared.finishCheck(release, failed: error != nil || status != 200)
                }
            }
        }.resume()
    }

    private func finishCheck(_ release: Release?, failed: Bool) {
        guard !failed, let release else {
            state = .failed(L("Couldn't reach GitHub. Try again later."))
            return
        }
        let defaults = UserDefaults.standard
        defaults.set(Date(), forKey: Key.checked)
        defaults.set(release.version, forKey: Key.version)
        defaults.set(release.package.absoluteString, forKey: Key.package)
        defaults.set(release.page?.absoluteString, forKey: Key.page)
        defaults.set(release.notes, forKey: Key.notes)
        available = Release.isNewer(release.version, than: Self.currentVersion) ? release : nil
        state = available == nil ? .upToDate : .idle
    }

    /// Downloads the installer into ~/Downloads, checks its signature and opens it in Installer.
    func install() {
        guard let release = available, state != .downloading else { return }
        state = .downloading
        URLSession.shared.downloadTask(with: release.package) { file, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 200
            var saved: URL?
            if let file, error == nil, status == 200 {
                let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                let target = downloads.appendingPathComponent("Seamtype-\(release.version).pkg")
                try? FileManager.default.removeItem(at: target)
                if (try? FileManager.default.moveItem(at: file, to: target)) != nil { saved = target }
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { Updater.shared.finishDownload(saved) }
            }
        }.resume()
    }

    private func finishDownload(_ package: URL?) {
        guard let package else {
            state = .failed(L("Couldn't download the update. Try again later."))
            return
        }
        guard Self.isSignedBySeamtype(package) else {
            try? FileManager.default.removeItem(at: package)
            state = .failed(L("The downloaded installer isn't signed by Seamtype's developer, so it was deleted."))
            return
        }
        state = .idle
        NSWorkspace.shared.open(package)
    }

    /// `pkgutil --check-signature`: a Developer ID Installer certificate with Seamtype's team,
    /// notarized by Apple.
    private static func isSignedBySeamtype(_ package: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/pkgutil")
        process.arguments = ["--check-signature", package.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return false }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return process.terminationStatus == 0
            && output.contains("Developer ID Installer:") && output.contains("(\(teamID))")
            && output.contains("Notarization: trusted")
    }
}
