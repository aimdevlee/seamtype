import ArasoCore
import Cocoa
import os

private let log = Logger(subsystem: "com.nyttastudio.inputmethod.Araso", category: "screen")

/// The text on screen in the front app's front window, for `Completion` to offer sentences from
/// where the app won't give its text to the input method (terminals): through Accessibility where
/// the app tells it (iTerm2). No screen capture: OCR made typing stutter. Kept in memory only, read again at
/// most every `maxAge` seconds, in the background: a key never waits for it.
@MainActor final class ScreenText {
    static let shared = ScreenText()

    /// Lines top to bottom as read the last time (empty: never read, or no permission).
    private(set) var text = ""
    private var readAt: Date = .distantPast
    private var reading = false
    private var asked = false
    static let maxAge: TimeInterval = 2
    /// The end of a long scrollback is what is on screen; counted once the padding is gone.
    nonisolated static let maxLength = 8000

    /// Starts a read when the last one is older than `maxAge`; `text` is updated when it is done.
    func refresh() {
        guard !reading, Date().timeIntervalSince(readAt) > Self.maxAge,
              let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        guard AXIsProcessTrusted() else {
            // Asked once per launch; the prompt points to its pane in System Settings.
            if !asked { asked = true; AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) }
            return
        }
        reading = true
        Task.detached {
            let accessed = Self.accessibleText(of: pid)
            // How much was read, never what: the screen's text stays out of the log.
            log.info("screen read via accessibility length=\(accessed?.text.count ?? 0) caret=\(accessed?.caret != nil)")
            let text = accessed.map { String(Completion.tidyScreen($0.text, caret: $0.caret).suffix(Self.maxLength)) }
            await MainActor.run {
                self.reading = false
                self.readAt = Date()
                if let text { self.text = text }
            }
        }
    }

    /// The focused element's text as the app gives it to Accessibility (VoiceOver), and where its
    /// caret is (UTF-16) when it says; nil when it gives no text.
    private nonisolated static func accessibleText(of pid: pid_t) -> (text: String, caret: Int?)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var focused: CFTypeRef?, value: CFTypeRef?, selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID(),
              AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String, !text.isEmpty else { return nil }
        var range = CFRange()
        let caret = AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextRangeAttribute as CFString, &selection) == .success
            && selection.map { AXValueGetValue($0 as! AXValue, .cfRange, &range) } == true ? range.location : nil
        return (text, caret)
    }

}
