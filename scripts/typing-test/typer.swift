// Types test scripts with real key events into the typing pane of Seamtype's own settings window
// (so they go through the input method) and compares the field's text with the expectation. The
// pane knows whether Seamtype is the input source in use and has a button to switch to it.
//
// usage: typer <cases.tsv> <Seamtype.app>    each line: script<TAB>expected
// script: characters as typed; ⏎ Return, ⎋ Esc, ⇧ Shift+Esc, ⌫ Delete, ← → arrows.
import AppKit
import Carbon

let keyCodes: [Character: (CGKeyCode, Bool)] = {
    var m: [Character: (CGKeyCode, Bool)] = [:]
    let lower: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
    ]
    for (c, k) in lower {
        m[c] = (k, false)
        m[Character(c.uppercased())] = (k, true)
    }
    let digits: [Character: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29]
    for (c, k) in digits { m[c] = (k, false) }
    m[" "] = (49, false); m[","] = (43, false); m["."] = (47, false); m["/"] = (44, false); m["?"] = (44, true)
    m["!"] = (18, true); m["-"] = (27, false); m["'"] = (39, false)
    m["@"] = (19, true); m["_"] = (27, true); m["("] = (25, true); m[")"] = (29, true)
    m["⏎"] = (36, false); m["⎋"] = (53, false); m["⇧"] = (53, true); m["⌫"] = (51, false)
    m["←"] = (123, false); m["→"] = (124, false)
    return m
}()

func press(_ ch: Character) {
    guard let (code, shift) = keyCodes[ch] else { fatalError("no key for \(ch)") }
    key(code, shift ? .maskShift : [])
    // Conversion (Space/Return in Japanese) and word commits take a moment.
    usleep(ch == " " || ch == "⏎" ? 250_000 : 45_000)
}

func key(_ code: CGKeyCode, _ flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)!
        e.flags = flags
        e.post(tap: .cghidEventTap)
        usleep(12_000)
    }
}

let cases = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
    .split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }

// The settings window on its typing tab, a process of its own.
let settings = Process()
settings.executableURL = URL(fileURLWithPath: CommandLine.arguments[2]).appendingPathComponent("Contents/MacOS/Seamtype")
settings.arguments = ["--settings", "typing"]
try! settings.run()
defer { settings.terminate() }
let window = AXUIElementCreateApplication(settings.processIdentifier)
sleep(2)

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
}
/// Every element under `element`, depth first. Some element in the window lists the application
/// among its children; following it again recursed until the stack overflowed.
func descendants(_ element: AXUIElement) -> [AXUIElement] {
    let children = (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        .filter { attribute($0, kAXRoleAttribute) as? String != kAXApplicationRole }
    return children + children.flatMap(descendants)
}
func front() {
    NSRunningApplication(processIdentifier: settings.processIdentifier)?.activate()
    usleep(300_000)
}
/// The typing field's text, read back through Accessibility.
func fieldText() -> String {
    let field = descendants(window).first { attribute($0, kAXRoleAttribute) as? String == kAXTextAreaRole }
    return field.flatMap { attribute($0, kAXValueAttribute) as? String } ?? "<no field>"
}
/// Empties the field: select all, then Delete (with nothing composing, both go to the field).
func clear() {
    key(0, .maskCommand) // ⌘A
    key(51, [])
    usleep(200_000)
}

front()
func typingThroughSeamtype() -> Bool {
    clear()
    for ch in "dkssud " { press(ch) }
    usleep(500_000)
    defer { clear() }
    return fieldText() == "안녕 "
}
// Right after an install macOS can take half a minute to hand keys to the new copy: keep trying,
// with the pane's own "Switch to Seamtype" button (shown while another input source is in use).
var ready = typingThroughSeamtype()
for _ in 0..<8 where !ready {
    if let button = descendants(window).first(where: {
        attribute($0, kAXRoleAttribute) as? String == kAXButtonRole
            && (attribute($0, kAXTitleAttribute) as? String ?? attribute($0, kAXDescriptionAttribute) as? String ?? "").contains("Seamtype")
    }) {
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }
    sleep(5)
    front()
    ready = typingThroughSeamtype()
}
guard ready else {
    print("Keys don't go through Seamtype in its settings window (dkssud didn't become 안녕): pick Seamtype in the input menu, then run again")
    settings.terminate() // exit skips the defer
    exit(2)
}
var passed = 0
for c in cases where c.count == 2 {
    let (script, expected) = (c[0], c[1].replacingOccurrences(of: "␣", with: " "))
    clear()
    for ch in script { press(ch) }
    usleep(500_000)
    let actual = fieldText()
    let ok = actual == expected
    if ok { passed += 1 }
    print("\(ok ? "PASS" : "FAIL")  \(script)  →  \(actual)\(ok ? "" : "   (expected \(expected))")")
    // Commit anything left composing before the next case.
    press("⏎")
}
let total = cases.filter { $0.count == 2 }.count
print("\(passed)/\(total) passed")
settings.terminate()
exit(passed == total ? 0 : 1)
