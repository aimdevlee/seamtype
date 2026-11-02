import Foundation

#if canImport(Darwin)
/// A terminal asking for a password (sudo, ssh): one of this user's terminals reads a line with
/// echo off, as a password prompt does (vim and other full-screen programs read raw keys, not
/// lines). Terminals that don't turn on Secure Event Input for it (Orca, Claude's) tell the input
/// method nothing, so the keys go to whichever app has focus as typed, as in a masked field.
/// - The input method can't tell which tty the focused tab is: another tab's prompt passes the
///   keys in every app until it ends (sudo gives up after 5 minutes).
/// - A prompt on the far side of ssh isn't seen: the local tty is raw while ssh runs.
/// - The tty has to be some process's controlling terminal, as a terminal tab's is: a pty only
///   written to (WebDriverAgent's output under xcodebuild, #83) can sit in that mode for hours
///   with nothing reading it.
public enum PasswordPrompt {
    /// Whether one of `devices` reads a password. A tty that isn't this user's, or isn't open,
    /// doesn't open and doesn't count. About 1–2 ms for 25–40 ttys.
    public static func isWaiting(devices: [String] = terminalDevices()) -> Bool {
        devices.contains { path in
            let fd = open(path, O_RDONLY | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else { return false }
            defer { close(fd) }
            var t = termios(), st = stat()
            return tcgetattr(fd, &t) == 0 && readsPassword(t.c_lflag)
                && fstat(fd, &st) == 0 && controlsAProcess(st.st_rdev)
        }
    }

    /// Whether some process has the tty `device` as its controlling terminal. Asked only of a tty
    /// in a password's mode, so the process table is read rarely.
    static func controlsAProcess(_ device: dev_t) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_TTY, Int32(bitPattern: UInt32(device))]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return false }
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / MemoryLayout<kinfo_proc>.stride + 1)
        size = procs.count * MemoryLayout<kinfo_proc>.stride
        // A failure (the table grew past the estimate's slack) counts as controlled: a prompt
        // missed types it into a word, a false one only leaves a word undecided.
        guard sysctl(&mib, 4, &procs, &size, nil, 0) == 0 else { return true }
        return size >= MemoryLayout<kinfo_proc>.stride
    }

    /// A line read with echo off.
    static func readsPassword(_ lflag: tcflag_t) -> Bool {
        lflag & tcflag_t(ICANON) != 0 && lflag & tcflag_t(ECHO) == 0
    }

    /// The pseudo-terminals' devices, `/dev/ttys*`.
    public static func terminalDevices() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? [])
            .filter { $0.hasPrefix("ttys") }.map { "/dev/" + $0 }
    }
}
#endif
