import SeamtypeCore
import SwiftUI

extension SwitchKey {
    /// The key's name in a sentence or a menu ("Right ⌥ tap").
    var displayName: String {
        switch self {
        case .rightOption: return L("Right ⌥ tap")
        case .optionSpace: return L("⌥Space")
        case .rightShift: return L("Right ⇧ tap")
        case .escape: return "Esc"
        case .shiftEscape: return "⇧Esc"
        }
    }

    /// What is printed on the keycap, as on a Mac keyboard.
    var glyph: String {
        switch self {
        case .rightOption: return "⌥"
        case .optionSpace: return "⌥ space"
        case .rightShift: return "⇧"
        case .escape: return "esc"
        case .shiftEscape: return "⇧ esc"
        }
    }

    /// Under the glyph: which of the two and how (a tap of the right one alone).
    var caption: String? {
        switch self {
        case .rightOption, .rightShift: return L("right, alone")
        case .optionSpace, .escape, .shiftEscape: return nil
        }
    }

    /// One line on what choosing it means, for its tooltip.
    var help: String {
        switch self {
        case .rightOption: return L("Tap the right ⌥ on its own. Apps ignore it, so nothing else happens.")
        case .optionSpace: return L("⌥ and Space together. It no longer types a no-break space.")
        case .rightShift: return L("Tap the right ⇧ on its own. Apps ignore it, so nothing else happens.")
        case .escape: return L("Quick, but Chromium apps (Slack, Claude) also see the Esc and may close or clear.")
        case .shiftEscape: return L("With nothing to change, it does nothing.")
        }
    }

    /// The keys in a few characters each, for a narrow column ("right ⌥, ⇧Esc").
    static func shortNames(_ keys: Set<SwitchKey>) -> String {
        keys.isEmpty ? L("None") : sorted(keys).map(\.label)
            .joined(separator: ", ")
    }

    /// On a small keycap: "right ⌥", "⌥Space", "Esc".
    var label: String { caption == nil ? displayName : L("right %@", glyph) }

    /// The keys in the settings' order.
    static func sorted(_ keys: Set<SwitchKey>) -> [SwitchKey] { allCases.filter(keys.contains) }
}

/// A key as a small keycap, the size of a list's: chosen ones are filled with the accent color.
struct Keycap: View {
    let key: SwitchKey
    let on: Bool
    var hovering = false
    var pressed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        Text(verbatim: key.label)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background {
                shape.fill(on ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    // The key's lower edge; it sinks while pressed.
                    .shadow(color: .black.opacity(on ? 0.25 : 0.1), radius: 0, y: pressed ? 0 : 1)
            }
            .overlay {
                shape.strokeBorder(on ? Color.clear : (contrast == .increased ? Color.primary : Color(nsColor: .separatorColor)))
            }
            .overlay { if hovering && !on { shape.fill(Color.primary.opacity(0.05)) } }
            .offset(y: pressed ? 0.5 : 0)
            .opacity(isEnabled ? 1 : 0.5)
    }
}

/// Keycaps to turn on and off, one per switch key.
struct KeycapToggles: View {
    let selection: Set<SwitchKey>
    let set: (SwitchKey, Bool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SwitchKey.allCases, id: \.self) { key in
                Toggle(key.displayName, isOn: Binding(get: { selection.contains(key) }, set: { set(key, $0) }))
                    .toggleStyle(KeycapToggleStyle(key: key))
            }
        }
    }
}

struct KeycapToggleStyle: ToggleStyle {
    let key: SwitchKey

    func makeBody(configuration: Configuration) -> some View {
        KeycapButton(key: key, isOn: configuration.$isOn)
    }

    private struct KeycapButton: View {
        let key: SwitchKey
        @Binding var isOn: Bool
        @State private var hovering = false

        var body: some View {
            Button { isOn.toggle() } label: { EmptyView() }
                .buttonStyle(Press(key: key, on: isOn, hovering: hovering))
                .onHover { hovering = $0 }
                .help(key.help)
                .accessibilityLabel(key.displayName)
                .accessibilityValue(isOn ? L("On") : L("Off"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .animation(.snappy(duration: 0.18), value: isOn)
        }
    }

    private struct Press: ButtonStyle {
        let key: SwitchKey
        let on: Bool
        let hovering: Bool

        func makeBody(configuration: Configuration) -> some View {
            Keycap(key: key, on: on, hovering: hovering, pressed: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}

/// A small keycap for a list: the keys an app uses, in a row.
struct MiniKeycaps: View {
    let keys: Set<SwitchKey>
    /// Following the default: drawn lighter.
    var inherited = false

    var body: some View {
        HStack(spacing: 4) {
            if keys.isEmpty {
                Label(L("None"), systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
            }
            ForEach(SwitchKey.sorted(keys), id: \.self) { key in
                Text(verbatim: key.label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
            }
        }
        .opacity(inherited ? 0.6 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.isEmpty ? L("None") : SwitchKey.sorted(keys).map(\.displayName).joined(separator: ", "))
    }
}
