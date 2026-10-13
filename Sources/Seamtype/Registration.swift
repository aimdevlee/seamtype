import AppKit
import Carbon

/// `Seamtype --register`, run from the freshly installed copy by every install path (the pkg's
/// postinstall, get.sh, install.sh), after the old process has been stopped.
@MainActor
enum Registration {
    /// Registers this bundle as an input method and enables its input source; returns the status.
    static func run() -> OSStatus {
        forgetOtherCopies()
        let filter = [kTISPropertyInputSourceID as String: SeamtypeSource.id] as CFDictionary
        func listed() -> TISInputSource? {
            (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource])?.first
        }
        // Always registered, even when macOS lists the source already: it may still point at a
        // copy that is about to go (the pkg replacing one in ~/Library), and then macOS drops the
        // source, and the user's choice to use it, when that copy disappears.
        let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
        // Enabling one the user has already added is left out, as Squirrel and vChewing do.
        if status == noErr, let source = listed(),
           TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled)
               .map({ CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque($0).takeUnretainedValue()) }) != true {
            TISEnableInputSource(source)
        }
        return status
    }

    /// `Seamtype --registered`: whether macOS lists the input source, enabled or not. The list is
    /// cached per process, so the pkg asks a fresh one after each `--register`: one run while
    /// LaunchServices was still taking in the replaced bundle reported success and left no source.
    static func isListed() -> Bool {
        let filter = [kTISPropertyInputSourceID as String: SeamtypeSource.id] as CFDictionary
        return !((TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []).isEmpty
    }

    /// Any other copy LaunchServices knows (a build folder, a stale download, an old path) can be
    /// the one macOS launches as the input method, and then nothing types until a restart.
    private static func forgetOtherCopies() {
        let ours = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
        for url in NSWorkspace.shared.urlsForApplications(withBundleIdentifier: SeamtypeSource.id)
        where url.resolvingSymlinksInPath().standardizedFileURL != ours {
            Uninstaller.launch(lsregister, ["-u", url.path])
        }
        Uninstaller.launch(lsregister, ["-f", ours.path])
    }
}
