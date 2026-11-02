#if canImport(Darwin)
import Foundation
import Testing
@testable import ArasoCore

/// A terminal waiting for a password gets the keys as typed (`PasswordPrompt`).
@Suite struct PasswordPromptTests {
    /// A process whose controlling terminal is `path`, as a terminal tab's shell is: a session of
    /// its own that opens the tty. Killed by the returned function.
    static func controlling(_ path: String) throws -> () -> Void {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSID))
        var pid: pid_t = 0
        let args = ["/bin/sh", "-c", "exec 3<\"$0\"; sleep 30", path]
        var argv = args.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        try #require(posix_spawn(&pid, "/bin/sh", nil, &attr, &argv, environ) == 0)
        let device = { () -> dev_t in var st = stat(); stat(path, &st); return st.st_rdev }()
        for _ in 0..<200 where !PasswordPrompt.controlsAProcess(device) { usleep(10_000) }
        return { kill(pid, SIGKILL); var status: Int32 = 0; waitpid(pid, &status, 0) }
    }

    /// A line read with echo off (sudo's prompt) is a password; echo on or raw keys (vim) aren't.
    @Test func passwordPromptIsALineReadWithEchoOff() throws {
        var master: Int32 = 0, slave: Int32 = 0
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        defer { close(master); close(slave) }
        let path = String(cString: ttyname(slave))
        let stop = try Self.controlling(path)
        defer { stop() }
        var t = termios()
        tcgetattr(slave, &t)
        #expect(!PasswordPrompt.isWaiting(devices: [path]))
        t.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(slave, TCSANOW, &t)
        #expect(PasswordPrompt.isWaiting(devices: [path]))
        t.c_lflag &= ~tcflag_t(ICANON)
        tcsetattr(slave, TCSANOW, &t)
        #expect(!PasswordPrompt.isWaiting(devices: [path]))
    }

    /// A pty in a password's mode that no process has as its controlling terminal (WebDriverAgent's
    /// output under xcodebuild, #83) isn't a prompt; once a session takes it, it is.
    @Test func ttyNoProcessControlsIsNotWaiting() throws {
        var master: Int32 = 0, slave: Int32 = 0
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        defer { close(master); close(slave) }
        let path = String(cString: ttyname(slave))
        var t = termios()
        tcgetattr(slave, &t)
        t.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(slave, TCSANOW, &t)
        #expect(!PasswordPrompt.isWaiting(devices: [path]))
        let stop = try Self.controlling(path)
        defer { stop() }
        #expect(PasswordPrompt.isWaiting(devices: [path]))
    }

    /// A tty that is gone, or a path that isn't one, doesn't count.
    @Test func missingDeviceIsNotWaiting() {
        #expect(!PasswordPrompt.isWaiting(devices: ["/dev/ttys-araso-missing", "/dev/null"]))
    }

    /// Without devices given, the user's pseudo-terminals are read: a new one is among them, and
    /// its prompt is seen. (Not the other way round: a real terminal may be asking meanwhile.)
    @Test func defaultDevicesSeeANewPseudoTerminal() throws {
        var master: Int32 = 0, slave: Int32 = 0
        try #require(openpty(&master, &slave, nil, nil, nil) == 0)
        defer { close(master); close(slave) }
        let devices = PasswordPrompt.terminalDevices()
        #expect(devices.contains(String(cString: ttyname(slave))))
        #expect(devices.allSatisfy { $0.hasPrefix("/dev/ttys") })
        let stop = try Self.controlling(String(cString: ttyname(slave)))
        defer { stop() }
        var t = termios()
        tcgetattr(slave, &t)
        t.c_lflag &= ~tcflag_t(ECHO)
        tcsetattr(slave, TCSANOW, &t)
        #expect(PasswordPrompt.isWaiting())
    }
}
#endif
