import AppKit
import Carbon
import ArasoCore

/// Uninstalling from the settings window's About tab, so nobody needs Terminal to remove the app:
/// the copies in both Input Methods folders go (the one the pkg put in /Library behind the
/// administrator prompt, with its receipt), the input source is switched away and disabled, the
/// running input method quits and the input menu forgets it. The settings files go only if asked.
@MainActor
enum Uninstaller {
    static let packageID = "com.nyttastudio.inputmethod.Araso.pkg"

    /// The installed copies: the terminal install (~/Library) and the pkg's (/Library), and
    /// Legato's and Seamtype's, left behind if an update from one didn't finish.
    static var installedCopies: [URL] {
        let user = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        let local = URL(fileURLWithPath: "/Library")
        return [user, local].compactMap { $0 }.flatMap { folder in
            (["Araso.app"] + Predecessor.all.map(\.appName)).map { folder.appendingPathComponent("Input Methods/\($0)") }
        }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Only an installed copy offers it: a development build has nothing to remove.
    static var isAvailable: Bool {
        Bundle.main.bundleURL.deletingLastPathComponent().lastPathComponent == "Input Methods"
    }

    /// Asks, uninstalls and quits; returns only if the user cancels.
    static func confirmAndRun() {
        let alert = NSAlert()
        alert.messageText = L("Uninstall Araso?")
        alert.informativeText = L("Araso is removed from your input sources and from this Mac. You can install it again any time.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L("Uninstall"))
        alert.addButton(withTitle: L("Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L("Also delete settings and learned words")
        alert.suppressionButton?.state = .off
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        // Looked up before the bundle, and its strings, are deleted.
        let failedTitle = L("Couldn't uninstall Araso"), doneTitle = L("Araso was uninstalled.")
        do {
            try run(deleteData: alert.suppressionButton?.state == .on)
        } catch Failure.cancelled {
            return
        } catch {
            let failed = NSAlert()
            failed.messageText = failedTitle
            failed.informativeText = error.localizedDescription
            failed.runModal()
            return
        }
        let done = NSAlert()
        done.messageText = doneTitle
        done.runModal()
        exit(0)
    }

    enum Failure: LocalizedError {
        case cancelled
        case script(String)
        var errorDescription: String? {
            if case .script(let message) = self { return message }
            return nil
        }
    }

    static func run(deleteData: Bool) throws {
        // Taken before the bundles go, while the input source system still lists them.
        let ids = [ArasoSource.id] + Predecessor.bundleIDs
        let ours = sources(installedToo: true).filter { ids.contains(property($0, kTISPropertyBundleID) ?? "") }

        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        // The one behind the password prompt first, and each copy unregistered only once it is
        // gone: Cancel there then leaves both copies installed and registered, as they were.
        let writable = { (copy: URL) in FileManager.default.isWritableFile(atPath: copy.deletingLastPathComponent().path) }
        for copy in installedCopies.sorted(by: { !writable($0) && writable($1) }) {
            if writable(copy) {
                try FileManager.default.removeItem(at: copy)
            } else {
                try removeAsAdministrator(copy)
            }
            Self.launch(lsregister, ["-u", copy.path])
        }

        if ArasoSource.isCurrent, let other = fallbackSource() { TISSelectInputSource(other) }
        for source in ours { TISDisableInputSource(source) }

        // The input method itself: same bundle identifier, any process but this one. Before the
        // data goes: switched away, it saves its kanji memory, which would bring the folder back.
        let running = ids.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        running.forEach { $0.forceTerminate() }
        for _ in 0..<30 where running.contains(where: { !$0.isTerminated }) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        if deleteData, let url = SupportDirectory.url, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        // The input menu and the switch indicator by the caret keep what they read first
        // (the indicator ignores SIGTERM), as scripts/pkg/postinstall does after installing.
        launch("/usr/bin/killall", ["TextInputMenuAgent"])
        launch("/usr/bin/killall", ["-KILL", "CursorUIViewService", "TextInputSwitcher"])
    }

    /// /Library needs an administrator: macOS's own password prompt, through AppleScript.
    private static func removeAsAdministrator(_ copy: URL) throws {
        let path = copy.path.replacingOccurrences(of: "'", with: "'\\''")
        // Its own receipt, and only once the copy is gone: a copy left behind keeps its receipt.
        let receipt = Predecessor.all.first { $0.appName == copy.lastPathComponent }?.packageID ?? packageID
        let shell = "rm -rf '\(path)' && { pkgutil --forget \(receipt) >/dev/null 2>&1; true; }"
        let prompt = L("Araso wants to remove itself from /Library/Input Methods.")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(shell)\" with prompt \"\(prompt)\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error {
            if error[NSAppleScript.errorNumber] as? Int == -128 { throw Failure.cancelled }
            throw Failure.script(error[NSAppleScript.errorMessage] as? String ?? L("Couldn't uninstall Araso"))
        }
        // A copy still there (or a script that couldn't be made) isn't an uninstall to go on from.
        if FileManager.default.fileExists(atPath: copy.path) { throw Failure.script(L("Couldn't uninstall Araso")) }
    }

    /// What to type with once Araso is gone: ABC or U.S. if enabled, else any other.
    static func fallbackSource() -> TISInputSource? {
        let others = sources(installedToo: false).filter {
            !([ArasoSource.id] + Predecessor.bundleIDs).contains(property($0, kTISPropertyBundleID) ?? "")
                && property($0, kTISPropertyInputSourceCategory) == kTISCategoryKeyboardInputSource as String
                && TISGetInputSourceProperty($0, kTISPropertyInputSourceIsSelectCapable)
                    .map { CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) } == true
        }
        let preferred = ["com.apple.keylayout.ABC", "com.apple.keylayout.US"]
        return others.first { preferred.contains(property($0, kTISPropertyInputSourceID) ?? "") } ?? others.first
    }

    private static func sources(installedToo: Bool) -> [TISInputSource] {
        TISCreateInputSourceList(nil, installedToo)?.takeRetainedValue() as? [TISInputSource] ?? []
    }

    private static func property(_ source: TISInputSource, _ key: CFString) -> String? {
        TISGetInputSourceProperty(source, key).map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String }
    }

    static func launch(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
