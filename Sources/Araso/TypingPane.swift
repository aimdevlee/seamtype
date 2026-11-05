import ArasoCore
import Carbon
import SwiftUI

/// Araso's own input source: is it the one in use, and switching to it.
enum ArasoSource {
    static let id = "com.nyttastudio.inputmethod.Araso"

    static var isCurrent: Bool { currentID == id }

    static var currentID: String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    static func select() {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return }
        TISSelectInputSource(source)
    }
}

/// The typing test: a field to type into through Araso, with how the word being typed (or
/// just committed) was decided: the language, how sure, and the heuristic's score per language,
/// as the input method reports it for this window.
struct TypingPane: View {
    @ObservedObject var model: SettingsModel
    @State private var text = ""
    @State private var current: TypingTrace?
    /// The field shows a word still being composed: it isn't in `text` until it's committed.
    @State private var composing = false
    @State private var arasoOn = ArasoSource.isCurrent
    @State private var adding: EntrySheet.Target?
    @FocusState private var focused: Bool

    var body: some View {
        Pane(tab: .typing) {
            SeamCard {
                VStack(alignment: .leading, spacing: 10) {
                    if !arasoOn {
                        HStack {
                            Label(L("Araso isn't the input source in use."), systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12)).foregroundStyle(Seam.warning)
                            Spacer()
                            Button(L("Switch to Araso")) {
                                ArasoSource.select()
                                arasoOn = ArasoSource.isCurrent
                                focused = true
                            }
                        }
                    }
                    TextEditor(text: $text)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Seam.ink)
                        .frame(minHeight: 96)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty && !composing {
                                Text(L("Type here on the English layout, e.g. dkssud hello"))
                                    .font(.system(size: 17, weight: .medium)).foregroundStyle(Seam.ink3)
                                    .padding(.leading, 5).allowsHitTesting(false)
                            }
                        }
                    HStack {
                        Text(L("The language switch key changes the word's reading, also right after the word."))
                            .font(.system(size: 12)).foregroundStyle(Seam.ink2)
                        Spacer()
                        Button(L("Clear")) {
                            text = ""
                            composing = false
                            current = nil
                            focused = true
                        }
                        .disabled(text.isEmpty && current == nil)
                    }
                }
                .padding(16)
            }
            HStack(spacing: 18) {
                Text(L("Examples")).font(.system(size: 12)).foregroundStyle(Seam.ink2)
                Example(keys: "dkssud githubdp", output: "안녕 github에")
                Example(keys: "hello TextEditdptj", output: "hello TextEdit에서")
                Example(keys: "kyouha ␣", output: "今日は")
            }
            .padding(.top, -8).padding(.leading, 2)
            SeamCard(title: L("How it was decided")) {
                VStack(alignment: .leading, spacing: 10) {
                    if let current {
                        TraceView(trace: current)
                        HStack {
                            Spacer()
                            Button(L("Add to Dictionary…")) { adding = .new(keys: current.keys) }
                        }
                    } else {
                        Text(L("Type a word above to see its scores."))
                            .font(.system(size: 13)).foregroundStyle(Seam.ink3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .sheet(item: $adding) { EntrySheet(model: model, target: $0) }
        .onAppear { focused = true; arasoOn = ArasoSource.isCurrent }
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
            arasoOn = ArasoSource.isCurrent
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
                            RoundedRectangle(cornerRadius: 3).fill(Seam.bg2)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Language(rawValue: Self.language(item.language))?.tint ?? Seam.ink3)
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
        Badge(title: language?.displayName ?? code, fill: (language?.tint ?? Seam.ink3).opacity(0.18),
              ink: language?.ink ?? Seam.ink2)
    }
}
