import SeamtypeCore
import Carbon
import SwiftUI

/// Seamtype's own input source: is it the one in use, and switching to it.
enum SeamtypeSource {
    static let id = "com.aimdevlee.inputmethod.Seamtype"

    static var isCurrent: Bool {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String == id
    }

    static func select() {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return }
        TISSelectInputSource(source)
    }
}

/// The typing test: a field to type into through Seamtype, with how the word being typed (or
/// just committed) was decided: the language, how sure, and the heuristic's score per language,
/// as the input method reports it for this window.
struct TypingPane: View {
    @ObservedObject var model: SettingsModel
    @State private var text = ""
    @State private var current: TypingTrace?
    /// The field shows a word still being composed: it isn't in `text` until it's committed.
    @State private var composing = false
    @State private var seamtypeOn = SeamtypeSource.isCurrent
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                if !seamtypeOn {
                    HStack {
                        Label(L("Seamtype isn't the input source in use."), systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Switch to Seamtype")) {
                            SeamtypeSource.select()
                            seamtypeOn = SeamtypeSource.isCurrent
                            focused = true
                        }
                    }
                }
                TextEditor(text: $text)
                    .font(.system(size: 15))
                    .frame(minHeight: 96)
                    .focused($focused)
                    .scrollContentBackground(.hidden)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty && !composing {
                            Text(L("Type here on the English layout, e.g. dkssud hello"))
                                .font(.system(size: 15)).foregroundStyle(.tertiary)
                                .padding(.leading, 5).allowsHitTesting(false)
                        }
                    }
                HStack {
                    Text(L("The language switch key changes the word's reading, also right after the word."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Clear")) {
                        text = ""
                        composing = false
                        current = nil
                        focused = true
                    }
                    .disabled(text.isEmpty && current == nil)
                }
            } footer: {
                HStack(spacing: 8) {
                    Example(keys: "dkssud githubdp", output: "안녕 github에")
                    Example(keys: "hello TextEditdptj", output: "hello TextEdit에서")
                    Example(keys: "kyouha ␣", output: "今日は")
                }
                .padding(.top, 4)
            }

            Section(L("How it was decided")) {
                if let current {
                    TraceView(trace: current)
                } else {
                    Text(L("Type a word above to see its scores."))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { focused = true; seamtypeOn = SeamtypeSource.isCurrent }
        // Marked text moves the selection; a search field's editor is a field editor, not this.
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { note in
            guard let textView = note.object as? NSTextView, !textView.isFieldEditor else { return }
            composing = textView.markedRange().length > 0
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: TypingTrace.name)) { note in
            guard let trace = TypingTrace(note.userInfo) else { return }
            current = trace
        }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String))) { _ in
            seamtypeOn = SeamtypeSource.isCurrent
        }
    }
}

/// The word being typed or just committed: keys → output, the language and how sure,
/// and a bar per language score (higher is likelier).
private struct TraceView: View {
    let trace: TypingTrace

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: trace.keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(verbatim: trace.output).font(.title3.weight(.semibold))
                Spacer()
                LanguageTag(code: trace.language)
                Text(verbatim: "\(Int((trace.confidence * 100).rounded()))%")
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            let scores = trace.scores
            if scores.isEmpty {
                Text(verbatim: trace.explanation).font(.caption.monospaced()).foregroundStyle(.secondary)
            } else {
                ForEach(scores, id: \.language) { item in
                    HStack(spacing: 8) {
                        Text(Language(rawValue: Self.language(item.language))?.displayName ?? item.language)
                            .font(.caption).frame(width: 64, alignment: .leading)
                        // A fixed track, no GeometryReader: inside a Form row that made the row too short.
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3).fill(.quaternary.opacity(0.4))
                            RoundedRectangle(cornerRadius: 3)
                                .fill((Language(rawValue: Self.language(item.language))?.tint ?? .gray).opacity(0.8))
                                .frame(width: Self.track * Self.fraction(item.score))
                        }
                        .frame(width: Self.track, height: 8)
                        Spacer(minLength: 0)
                        Text(verbatim: String(format: "%.2f", item.score))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                    }
                }
                Text(verbatim: trace.explanation).font(.caption2.monospaced()).foregroundStyle(.tertiary)
            }
            if let previous = trace.previous, let language = Language(rawValue: previous) {
                Text(L("After a %@ word", language.displayName)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 4)
    }

    static let track: CGFloat = 300

    static func language(_ code: String) -> String {
        ["en": "english", "ko": "korean", "ja": "japanese"][code] ?? code
    }

    /// Scores run from about -9 (gibberish) to -1 (very likely) per keystroke.
    static func fraction(_ score: Double) -> CGFloat {
        CGFloat(min(max((score + 9) / 8, 0.03), 1))
    }
}

private struct LanguageTag: View {
    let code: String

    var body: some View {
        let language = Language(rawValue: code)
        Text(language?.displayName ?? code)
            .font(.caption)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((language?.tint ?? .gray).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
    }
}
