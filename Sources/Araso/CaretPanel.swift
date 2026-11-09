import ArasoCore
import Cocoa

/// A small panel under the caret that never takes focus: what PauseHUD, the strip of a word's
/// readings and the card of kana→kanji candidates are shown in.
@MainActor enum CaretPanel {
    /// The system's input source indicator, measured on screen: its capsule's height and its gap
    /// below the caret. PauseHUD is one, and the strip's thumb is one.
    static let indicatorHeight: CGFloat = 23
    static let indicatorGap: CGFloat = 4

    /// The indicator's blue: the accent color's sRGB components taken as Display P3, more vivid
    /// than the accent color itself (measured against it on screen).
    static var indicatorFill: NSColor {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        return NSColor(displayP3Red: accent.redComponent, green: accent.greenComponent, blue: accent.blueComponent, alpha: 1)
    }

    static func make(size: NSSize) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        return panel
    }

    /// Just under the caret's line (above it near the bottom of the screen), kept on screen:
    /// centered on the caret, or starting where it does. Without a caret, near the top of the
    /// screen the mouse is on.
    static func origin(for size: NSSize, caret: NSRect, gap: CGFloat, centered: Bool) -> NSPoint {
        let anchor = caret == .zero ? NSEvent.mouseLocation : caret.origin
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return anchor }
        var point: NSPoint
        if caret == .zero {
            point = NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 40)
        } else {
            let x = centered ? caret.midX.rounded() - size.width / 2 : caret.minX.rounded()
            point = NSPoint(x: x, y: caret.minY - gap - size.height)
            if point.y < visible.minY { point.y = caret.maxY + gap }
        }
        point.x = min(max(point.x, visible.minX), visible.maxX - size.width)
        point.y = min(max(point.y, visible.minY), visible.maxY - size.height)
        return point
    }
}

/// The switch key being held, on the word it is about: nothing for a tap's moment, then a red pen's
/// wave under the word, from its first letter to its last, for the half second a long press takes
/// (`InputController.switchTapChanged`), then a heavier stroke: letting go now lists the guesses. Its
/// own mark under the app's underline, which an input method can't color bit by bit, so it doesn't
/// have to land exactly on it.
@MainActor enum LongPressWave {
    private static let height: CGFloat = 10
    private static let appears = 0.12
    private static let ready = 0.5
    private static var panel: NSPanel?
    private static var generation = 0

    /// `word`: its place on screen. `y`: the wave's middle.
    static func start(word: NSRect, y: CGFloat) {
        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + appears) {
            guard current == generation else { return }
            show(word: word, y: y, current: current)
        }
    }

    static func hide() {
        generation += 1
        panel?.orderOut(nil)
    }

    private static func show(word: NSRect, y: CGFloat, current: Int) {
        let size = NSSize(width: word.width, height: height)
        let panel = panel ?? CaretPanel.make(size: size)
        self.panel = panel
        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        // A window goes on whole points, so the wave's place is made inside the panel.
        let bottom = (y - height / 2).rounded(.down)
        let middle = y - bottom
        let wave = CGMutablePath()
        wave.move(to: CGPoint(x: 0, y: middle))
        var at: CGFloat = 0, up = true
        while at < size.width {
            let next = min(at + 3, size.width)
            wave.addQuadCurve(to: CGPoint(x: next, y: middle), control: CGPoint(x: (at + next) / 2, y: middle + (up ? 3 : -3)))
            at = next
            up.toggle()
        }
        func stroke(_ color: NSColor, width: CGFloat) -> CAShapeLayer {
            let shape = CAShapeLayer()
            shape.path = wave
            shape.fillColor = nil
            shape.lineWidth = width
            shape.lineCap = .round
            view.effectiveAppearance.performAsCurrentDrawingAppearance { shape.strokeColor = color.cgColor }
            view.layer?.addSublayer(shape)
            return shape
        }
        _ = stroke(Paper.redPen.withAlphaComponent(0.25), width: 1.5)
        let fill = stroke(Paper.redPen, width: 1.5)
        // Before the panel shows, or its first frame has the wave whole.
        if !reduceMotion {
            let grow = CABasicAnimation(keyPath: "strokeEnd")
            grow.fromValue = 0
            grow.toValue = 1
            grow.duration = ready - appears
            fill.add(grow, forKey: "fill")
        }
        panel.contentView = view
        panel.setFrame(NSRect(origin: NSPoint(x: word.minX, y: bottom), size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + ready - appears) {
            guard current == generation else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fill.lineWidth = 2.25
            CATransaction.commit()
        }
    }
}

/// Lays its subviews out top-down.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Motion keeps out of the way of typing: each animation is short, and none when the user
/// asked the system for less motion.
@MainActor private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

@MainActor private func animate(_ duration: TimeInterval, _ curve: CAMediaTimingFunction? = nil,
                                _ changes: @escaping () -> Void, done: (() -> Void)? = nil) {
    NSAnimationContext.runAnimationGroup({ context in
        context.duration = reduceMotion ? 0 : duration
        context.timingFunction = curve
        context.allowsImplicitAnimation = true
        changes()
    }, completionHandler: { MainActor.assumeIsolated { done?() } })
}

/// Fast out, gentle in: a move that is over before the next key.
private let ease = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

/// Araso's paper, as on the website and in the settings window: the strip's track, birch paper
/// and navy ink, navy paper in the dark.
@MainActor enum Paper {
    static let background = dynamic(0xfaf8f4, 0x0d213b)
    static let ink2 = dynamic(0x4a5b70, 0xa9b6c6)
    static let line = dynamic(0xe6e1d8, 0xf3f1ec, darkAlpha: 0.16)
    /// The capsule of a word that went back to Araso's own reading: nothing remembered any more.
    static let reset = dynamic(0x6e6e73, 0x636366)
    /// A red pen, what marks a guess: the long press's wave under the word, and what a guess
    /// changed, in this color with a wave under it.
    static let redPen = dynamic(0xc62828, 0xff6b5f)

    static func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark, alpha: darkAlpha) : rgb(light, alpha: 1)
        }
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
    }
}

/// What the dictionary knows about a reading, shown after it in the strip: a check where it
/// remembers it (corrected twice, or added by hand), a pencil where it was corrected once.
private enum Mark: Equatable { case remembered, once }

private extension InputSession.Readings {
    func mark(_ index: Int) -> Mark? {
        index == remembered ? .remembered : index == once ? .once : nil
    }
}

/// A mark's 11 pt square: the pencil and the arrow back as SF Symbols, the check as a stroke so it
/// can draw itself when a word is learned. Each moves about its own center.
private final class MarkView: NSView {
    enum Kind { case check, pencil, back }
    static let side: CGFloat = 11
    private(set) var kind: Kind?
    private var shape: CALayer?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.side, height: Self.side))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    /// Shows `kind` (nil: nothing) in `color`.
    func show(_ kind: Kind?, color: NSColor) {
        shape?.removeFromSuperlayer()
        shape = nil
        self.kind = kind
        guard let kind, let layer else { return }
        let shape: CALayer
        if kind == .check {
            let check = CAShapeLayer()
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 1.6, y: 5.6))
            path.addLine(to: CGPoint(x: 4.4, y: 2.6))
            path.addLine(to: CGPoint(x: 9.6, y: 8.9))
            check.path = path
            check.fillColor = nil
            check.lineWidth = 1.9
            check.lineCap = .round
            check.lineJoin = .round
            shape = check
        } else {
            shape = CALayer()
            shape.contentsGravity = .resizeAspect
            shape.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        }
        shape.frame = bounds
        layer.addSublayer(shape)
        self.shape = shape
        tint(color)
    }

    func tint(_ color: NSColor) {
        var resolved = color.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        if let check = shape as? CAShapeLayer {
            check.strokeColor = resolved
        } else if let kind, let shape {
            let name = kind == .pencil ? "pencil" : "arrow.uturn.backward"
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
                .applying(.init(paletteColors: [NSColor(cgColor: resolved) ?? color]))
            shape.contents = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }
    }

    /// The check draws itself, the short stroke then the long one.
    func draw(_ duration: CFTimeInterval) {
        guard let check = shape as? CAShapeLayer, !reduceMotion else { return }
        let draw = CABasicAnimation(keyPath: "strokeEnd")
        draw.fromValue = 0
        draw.toValue = 1
        draw.duration = duration
        draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
        check.add(draw, forKey: "draw")
    }

    /// Comes up from small, a little past its size and back.
    func popIn() {
        guard let shape, !reduceMotion else { return }
        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [0.4, 1.15, 1]
        grow.keyTimes = [0, 0.6, 1]
        grow.duration = 0.22
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.12
        shape.add(grow, forKey: "grow")
        shape.add(fade, forKey: "fade")
    }

    /// Goes small and away, then `done`.
    func popOut(_ done: @escaping () -> Void) {
        guard let shape, !reduceMotion else { return done() }
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.toValue = 0.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.toValue = 0
        for animation in [shrink, fade] {
            animation.duration = 0.12
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
            shape.add(animation, forKey: animation.keyPath)
        }
        CATransaction.commit()
    }

    /// The pencil writes: a quick wobble about its point.
    func wiggle() {
        guard let shape, !reduceMotion else { return }
        let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        turn.values = [0, 0.3, -0.18, 0.07, 0].map { $0 as NSNumber }
        turn.duration = 0.45
        turn.beginTime = CACurrentMediaTime() + 0.1
        shape.add(turn, forKey: "wiggle")
    }

    /// The arrow turns back once, as it points.
    func spin() {
        guard let shape, !reduceMotion else { return }
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = -CGFloat.pi * 1.8
        turn.toValue = 0
        turn.duration = 0.5
        turn.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0.9, 0.3, 1)
        shape.add(turn, forKey: "spin")
    }
}

private extension Language {
    /// The language in its own script, as short as a row's end has room for.
    var script: String {
        switch self {
        case .english: return "A"
        case .korean: return "아"
        case .japanese: return "あ"
        case .mixed: return "A아"
        }
    }
}

/// How large a cell's text sits: a capsule on its own is the system indicator's size, a card's rows
/// are for reading, kanji above all, and a little taller.
@MainActor private struct CellLook {
    let height: CGFloat
    let font: NSFont
    /// The line every text of the cell sits on, numbers and outcome words too: the text's cap height
    /// centered in the row. Marks are centered on the same middle, so a check or a pencil sits level
    /// with the letters rather than with the label's frame, which hangs lower.
    var baseline: CGFloat { (height + font.capHeight) / 2 }

    static let capsule = CellLook(height: CaretPanel.indicatorHeight, font: .systemFont(ofSize: 13, weight: .medium))
    static let row = CellLook(height: 26, font: .systemFont(ofSize: 15, weight: .medium))
}

/// One reading of the strip or candidate of the card: its number (candidates), its text cut at
/// 220 pt, its mark and language (readings). White on the thumb, the paper's ink beside it.
private final class StripCell: NSView {
    static let pad: CGFloat = 10
    static let maxText: CGFloat = 220
    /// The numbers' digits are all as wide, so the candidates start at one x down the card.
    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let numberWidth = ceil(number(8).fittingSize.width) + 1
    private static let measure: NSTextField = {
        let label = Paper.label("", size: 15, weight: .medium)
        label.font = CellLook.row.font
        return label
    }()

    /// Puts `label` at `x`, its baseline on `baseline`, kept on a backing pixel.
    static func place(_ label: NSTextField, x: CGFloat, width: CGFloat? = nil, baseline: CGFloat) {
        let size = label.fittingSize
        label.frame = NSRect(x: x, y: 0, width: width ?? ceil(size.width) + 1, height: size.height)
        label.setFrameOrigin(NSPoint(x: x, y: ((baseline - label.firstBaselineOffsetFromTop) * 2).rounded() / 2))
    }

    /// Where a mark's square goes after `x`: centered on the letters' middle.
    private func markOrigin(after x: CGFloat) -> NSPoint {
        NSPoint(x: x + 5, y: look.baseline - look.font.capHeight / 2 - MarkView.side / 2)
    }

    private static func number(_ n: Int) -> NSTextField {
        let label = Paper.label("\(n)", size: 11, weight: .medium)
        label.font = numberFont
        return label
    }

    /// How wide a numbered cell for `string` is, without making one.
    static func width(numbered string: String) -> CGFloat {
        pad + numberWidth + 3 + textWidth(string) + pad
    }

    /// How wide `string` is in a card's row, cut as a cell cuts it.
    static func textWidth(_ string: String) -> CGFloat {
        measure.stringValue = string
        return min(ceil(measure.fittingSize.width) + 1, maxText)
    }

    /// The card's footer, the reading and the page: its digits as wide as each other too, so the
    /// page count doesn't move it.
    static func footer(_ text: String) -> NSTextField {
        let label = Paper.label(text, size: 11)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        label.textColor = Paper.ink2
        return label
    }
    let text: NSTextField
    private let look: CellLook
    /// Which language the reading is, in its own script, at the row's end.
    private let languageLabel: NSTextField?
    private let number: NSTextField?
    private let mark: Mark?
    private var markView: MarkView?
    /// What a guess changed, as a range of the text, and the wave under it.
    private var changed: NSRange?
    private var wave: CAShapeLayer?
    private var outcome: NSTextField?
    /// How far the text and the mark move left when the number goes (`dropNumber`).
    private var numberRoom: CGFloat = 0

    override var isFlipped: Bool { true }

    /// `changed`: a guess, with which of its characters differ from the keys' own reading.
    /// `markColumn`: where the list's marks stand, past the widest text, so they line up; nil
    /// when nothing in the list has one.
    init(_ string: String, number: Int? = nil, mark: Mark? = nil, changed: Range<Int>? = nil,
         look: CellLook? = nil, markColumn: CGFloat? = nil, language: Language? = nil) {
        let look = look ?? .capsule
        self.look = look
        text = Paper.label(string, size: 13, weight: .medium)
        text.font = look.font
        self.number = number.map(Self.number)
        self.mark = mark
        languageLabel = language.map { Paper.label($0.script, size: 12, weight: .semibold) }
        super.init(frame: .zero)
        var x = Self.pad
        if let number = self.number {
            Self.place(number, x: x, baseline: look.baseline)
            addSubview(number)
            x = number.frame.maxX + 3
        }
        Self.place(text, x: x, width: min(ceil(text.fittingSize.width) + 1, Self.maxText), baseline: look.baseline)
        addSubview(text)
        if let changed { underline(changed, of: string, x: x) }
        x = max(text.frame.maxX, x + (markColumn ?? 0))
        if let mark {
            let view = MarkView()
            view.setFrameOrigin(markOrigin(after: x))
            addSubview(view)
            view.show(mark == .remembered ? .check : .pencil, color: Paper.ink2)
            markView = view
        }
        if markColumn != nil { x += 5 + MarkView.side }
        if let languageLabel {
            Self.place(languageLabel, x: x + 10, baseline: look.baseline)
            addSubview(languageLabel)
            x = languageLabel.frame.maxX
        }
        frame = NSRect(x: 0, y: 0, width: x + Self.pad, height: look.height)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        var spoken = switch mark {
        case .remembered: "\(string), \(L("Remembered"))"
        case .once: "\(string), \(L("Corrected once"))"
        case nil: string
        }
        if let language { spoken += ", \(language.displayName)" }
        setAccessibilityLabel(spoken)
    }

    /// The language stays at the row's end, however wide the card made the row.
    func alignLanguage() {
        guard let languageLabel else { return }
        languageLabel.setFrameOrigin(NSPoint(x: frame.width - Self.pad - languageLabel.frame.width, y: languageLabel.frame.minY))
    }

    required init?(coder: NSCoder) { nil }

    /// The wave under `range` of the characters: AppKit's underlines have no wavy style.
    private func underline(_ range: Range<Int>, of string: String, x: CGFloat) {
        guard !range.isEmpty else { return }
        let characters = Array(string)
        let before = String(characters.prefix(range.lowerBound)).utf16.count
        changed = NSRange(location: before, length: String(characters[range]).utf16.count)
        let attributes: [NSAttributedString.Key: Any] = [.font: look.font]
        func width(_ count: Int) -> CGFloat { (String(characters.prefix(count)) as NSString).size(withAttributes: attributes).width }
        let start = x + 2 + width(range.lowerBound), end = min(x + 2 + width(range.upperBound), x + Self.maxText)
        let y = look.baseline + 3
        let path = CGMutablePath()
        path.move(to: CGPoint(x: start, y: y))
        var at = start, up = true
        while at < end {
            let next = min(at + 2, end)
            path.addQuadCurve(to: CGPoint(x: next, y: y), control: CGPoint(x: (at + next) / 2, y: y + (up ? -1.5 : 1.5)))
            at = next
            up.toggle()
        }
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = nil
        shape.lineWidth = 1
        wantsLayer = true
        layer?.addSublayer(shape)
        wave = shape
    }

    func color(on: Bool) {
        let ink = on ? NSColor.white : Paper.ink2
        text.textColor = ink
        if let changed {
            let styled = NSMutableAttributedString(string: text.stringValue, attributes: [.font: look.font, .foregroundColor: ink])
            if !on { styled.addAttribute(.foregroundColor, value: Paper.redPen, range: changed) }
            text.attributedStringValue = styled
        }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            wave?.strokeColor = on ? NSColor.white.withAlphaComponent(0.85).cgColor : Paper.redPen.cgColor
        }
        number?.textColor = ink
        languageLabel?.textColor = ink
        markView?.tint(on ? .white : mark == .remembered ? CaretPanel.indicatorFill : Paper.ink2)
    }

    /// Makes room after the text for what a correction did (the mark's place, then `word`) and
    /// returns the width it now takes, without the number: the reading is chosen, and its text is
    /// to land on the word's first letter, as an unnumbered cell's does.
    func makeRoom(for word: String) -> CGFloat {
        numberRoom = number == nil ? 0 : text.frame.minX - Self.pad
        languageLabel?.isHidden = true
        let view = markView ?? {
            let view = MarkView()
            addSubview(view)
            markView = view
            return view
        }()
        // Next to the text, wherever the list's marks stood: this capsule has only this reading.
        view.setFrameOrigin(markOrigin(after: text.frame.maxX))
        let label = Paper.label(word, size: 12, weight: .semibold)
        label.textColor = .white
        Self.place(label, x: view.frame.maxX - numberRoom + 6, baseline: look.baseline)
        label.alphaValue = 0
        addSubview(label)
        outcome = label
        setFrameSize(NSSize(width: label.frame.maxX + Self.pad, height: frame.height))
        return frame.width
    }

    /// The number goes and the text and the mark move into the room `makeRoom` left them; called
    /// inside an animation, they move with the capsule.
    func dropNumber() {
        guard let number, numberRoom > 0 else { return }
        number.animator().alphaValue = 0
        for view in [text, markView].compactMap({ $0 }) {
            view.animator().setFrameOrigin(NSPoint(x: view.frame.minX - numberRoom, y: view.frame.minY))
        }
        numberRoom = 0
    }

    /// What a correction did: a pencil that writes once, the check drawing itself when learned
    /// (the pencil of the first correction making way), the arrow back turning when forgotten.
    func say(_ learning: DictionaryEngine.Learning) {
        animate(0.2, ease, { self.outcome?.animator().alphaValue = 1 })
        guard let view = markView else { return }
        switch learning {
        case .once:
            if view.kind != .pencil { view.show(.pencil, color: .white); view.popIn() }
            view.wiggle()
        case .forGood:
            let check = { view.show(.check, color: .white); view.draw(0.3) }
            if view.kind == .pencil { view.popOut(check) } else { check() }
        case .forgot:
            view.show(.back, color: .white)
            view.popIn()
            view.spin()
        }
    }
}

/// The switch key's readings on one strip under the word, the kana→kanji candidates in a card under
/// the clause, until the next key (`InputSession.readings`, `.conversion`): the system's input
/// source indicator, its blue capsule white inside, as the thumb on what's on screen, the others on
/// Araso's paper beside it or below it, each as it would go in, so the next presses can be read off.
/// The thumb moves in 0.12 s and the next key cuts it short. A click chooses too. When the key after
/// a switch made the dictionary take the correction (`InputSession.learned`), the paper closes onto
/// the chosen reading, whose capsule moves under the word and says what happened.
/// The panel is a little larger than the strip, for the shadow the views cast themselves: only
/// views move, never the window, so what moves stays in step and keeps its shadow.
@MainActor enum StripHUD {
    private enum Shown: Equatable {
        case readings([String], [Mark?], numbered: Bool)
        case candidates([String], page: Int)
        case suggestions([String])
    }

    /// A capsule on its own on one line; the readings and candidates in a card `width` wide and
    /// `rows` tall on every page, so turning one doesn't move anything, the candidates' reading and
    /// page (`footer`) under a hairline below them.
    private enum Layout {
        case row
        case card(width: CGFloat, rows: Int, footer: (reading: String, page: String?)?)
    }

    private static var panel: NSPanel?
    private static var root: NSView?
    private static var strip: NSView?
    private static var track: NSView?
    /// The card's rows, nil for a capsule on its own.
    private static var clip: NSView?
    /// The card is above the word, the screen's bottom being near.
    private static var above = false
    private static var thumb: NSView?
    private static var cells: [StripCell] = []
    private static var shown: Shown?
    private static var selected = 0
    private static var languages: [Language] = []
    private static var pageStart = 0
    private static var pick: ((Language) -> Void)?
    private static var choose: ((Int) -> Void)?
    /// Bumped on every show and hide, so a fade left from before stops.
    private static var generation = 0
    private static var hiding = false
    /// Saying what a correction did; the keys typed meanwhile don't put it away.
    private static var settling = false

    private static let height = CaretPanel.indicatorHeight
    private static let pageSize = InputSession.Conversion.pageSize
    /// Room around the strip for its shadow.
    private static let margin: CGFloat = 12
    /// The card's paper around its rows, and the room under them for the footer.
    private static let inset: CGFloat = 4
    private static let footerHeight: CGFloat = 24
    /// The card's width for the candidates it was last measured for.
    private static var measured: (texts: [String], footer: String, width: CGFloat)?

    private static var isUp: Bool { panel?.isVisible == true && !hiding }

    /// `word` is the word's line in screen coordinates; without one (`.zero`) nothing is shown,
    /// since readings away from the word say little. `pick` switches to a reading clicked.
    static func show(_ readings: InputSession.Readings, word: NSRect, pick: @escaping (Language) -> Void) {
        guard word != .zero else { return hide(force: true) }
        self.pick = pick
        choose = nil
        generation += 1
        let marks = readings.texts.indices.map { readings.mark($0) }
        let next = Shown.readings(readings.texts, marks, numbered: readings.numbered)
        if isUp, !settling, shown == next {
            select(readings.selected)
        } else {
            settling = false
            pageStart = 0
            let markColumn = marks.contains { $0 != nil } ? readings.texts.map(StripCell.textWidth).max() : nil
            let cells = readings.texts.indices.map {
                StripCell(readings.texts[$0], number: readings.numbered && $0 < 9 ? $0 + 1 : nil, mark: marks[$0], look: .row,
                          markColumn: markColumn, language: readings.languages.indices.contains($0) ? readings.languages[$0] : nil)
            }
            let width = ceil(cells.map(\.frame.width).max() ?? 0) + inset * 2
            build(cells, layout: .card(width: width, rows: cells.count, footer: nil),
                  selected: readings.selected, word: word)
        }
        shown = next
        languages = readings.languages
        let text = readings.texts[readings.selected]
        root?.setAccessibilityLabel(L("Readings, %@ selected", text))
        announce(L("%@, %ld of %ld", text, readings.selected + 1, readings.texts.count))
    }

    /// What Tab finishes the word being typed with, in a card under it; `selected` is the one
    /// Tab put in its place, else the first is on the thumb, as the one Tab takes next.
    static func show(suggestions: [String], selected: Int?, word: NSRect) {
        guard word != .zero else { return hide(force: true) }
        let next = Shown.suggestions(suggestions)
        if isUp, !settling, shown == next { return select(selected ?? 0) }
        pick = nil
        choose = nil
        generation += 1
        settling = false
        pageStart = 0
        let footer = "⇥"
        build(suggestions.map { StripCell($0) },
              layout: .card(width: cardWidth(suggestions, footer: footer), rows: suggestions.count, footer: (footer, nil)),
              selected: selected ?? 0, word: word)
        shown = next
        root?.setAccessibilityLabel(L("Suggestions, %@ selected", suggestions[selected ?? 0]))
    }

    /// `clause` is where the clause being converted starts; `choose` commits candidate `index` of
    /// the whole list. A card under the clause, nine rows to a page numbered for the digits, the
    /// reading and the page under them; as wide as the widest candidate on any page.
    static func show(_ conversion: InputSession.Conversion, clause: NSRect, choose: @escaping (Int) -> Void) {
        self.choose = choose
        pick = nil
        generation += 1
        let texts = conversion.candidates.map(\.text)
        let page = conversion.selected / pageSize
        let next = Shown.candidates(texts, page: page)
        if isUp, !settling, shown == next {
            select(conversion.selected % pageSize)
        } else {
            var turn: CGFloat?
            if isUp, !settling, case .candidates(texts, let old)? = shown { turn = page > old ? 1 : -1 }
            settling = false
            pageStart = page * pageSize
            let pages = (texts.count + pageSize - 1) / pageSize
            let pageText = { (page: Int) in pages > 1 ? "\(page + 1)/\(pages)" : nil }
            let cells = texts[pageStart..<min(pageStart + pageSize, texts.count)].enumerated().map {
                StripCell($1, number: $0 + 1, look: .row)
            }
            let widest = conversion.kana + (pageText(pages - 1).map { "   " + $0 } ?? "")
            build(cells, layout: .card(width: cardWidth(texts, footer: widest), rows: min(pageSize, texts.count),
                                       footer: (conversion.kana, pageText(page))),
                  selected: conversion.selected % pageSize, word: clause, turn: turn)
        }
        shown = next
        root?.setAccessibilityLabel(L("Candidates, %@ selected", conversion.current.text))
    }

    /// The long press's guesses for the word (`InputSession.guesses`): a card as the candidates' (five
    /// at most, numbered for the digits), what each changed colored with a wave under it, opening
    /// from the guess in the word's place; `choose` picks guess `index`.
    /// With no guesses, a moment's note that there are none.
    static func show(_ guesses: InputSession.Guesses, word: NSRect, choose: @escaping (Int) -> Void) {
        guard !guesses.texts.isEmpty else { return note(L("No guesses"), word: word, neutral: true) }
        self.choose = choose
        pick = nil
        generation += 1
        let next = Shown.candidates(guesses.texts, page: 0)
        if isUp, !settling, shown == next {
            select(guesses.selected)
        } else {
            settling = false
            pageStart = 0
            let cells = guesses.texts.enumerated().map { StripCell($1, number: $0 + 1, changed: guesses.changed[$0], look: .row) }
            let width = ceil(cells.map(\.frame.width).max() ?? 0) + inset * 2
            build(cells, layout: .card(width: width, rows: cells.count, footer: nil),
                  selected: guesses.selected, word: word, unfolds: true)
        }
        shown = next
        let text = guesses.texts[guesses.selected]
        root?.setAccessibilityLabel(L("Guesses, %@ selected", text))
        announce(L("%@, %ld of %ld", text, guesses.selected + 1, guesses.texts.count))
    }

    /// `text` in a capsule under the word for a moment (a word fixed at its end), as a correction's is;
    /// the keys typed meanwhile don't put it away. `neutral`: gray, as blue says something was chosen
    /// or done, and here nothing was.
    static func note(_ text: String, word: NSRect, neutral: Bool = false) {
        guard word != .zero else { return }
        choose = nil
        pick = nil
        pageStart = 0
        build([StripCell(text)], layout: .row, selected: 0, word: word)
        if neutral, let thumb {
            var gray = Paper.reset.cgColor
            thumb.effectiveAppearance.performAsCurrentDrawingAppearance { gray = Paper.reset.cgColor }
            thumb.layer?.backgroundColor = gray
        }
        generation += 1
        let current = generation
        shown = nil
        settling = true
        panel?.ignoresMouseEvents = true
        root?.setAccessibilityLabel(text)
        announce(text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard current == generation, let panel else { return }
            animate(0.25, nil, { panel.animator().alphaValue = 0 }) {
                guard current == generation else { return }
                panel.orderOut(nil)
                settling = false
            }
        }
    }

    /// Wide enough for every candidate in `texts`, whichever page it is on, and for `footer`, the
    /// widest the footer gets (the last page's count, its digits as wide as any).
    private static func cardWidth(_ texts: [String], footer: String) -> CGFloat {
        if let measured, measured.texts == texts, measured.footer == footer { return measured.width }
        let widest = texts.map(StripCell.width(numbered:)).max() ?? 0
        let footerWidth = ceil(StripCell.footer(footer).fittingSize.width) + 1 + StripCell.pad * 2
        let width = ceil(max(widest, footerWidth)) + inset * 2
        measured = (texts, footer, width)
        return width
    }

    /// Puts the strip away; one saying what a correction did stays its moment unless `force`d
    /// (the field lost focus, the input method paused).
    static func hide(force: Bool = false) {
        guard let panel, panel.isVisible, !hiding, force || !settling else { return }
        generation += 1
        let current = generation
        hiding = true
        settling = false
        shown = nil
        animate(0.1, CAMediaTimingFunction(name: .easeIn), { panel.animator().alphaValue = 0 }) {
            guard current == generation else { return }
            panel.orderOut(nil)
            hiding = false
        }
    }

    /// The correction the dictionary just took: the card itself becomes the chosen reading's
    /// capsule, under the word's first letter, and says what happened, a pencil and "Noted"
    /// after the first correction, the check drawing itself and "Learned" once learned for good,
    /// the arrow back and "Reset" on gray when a switch back to Araso's own reading forgot the
    /// word. Without a strip up (`word`, the word's line, places it) the capsule shows on its own.
    static func settle(_ learned: InputSession.Learned, word: NSRect) {
        let index: Int
        if isUp, !settling, case .readings? = shown, cells.indices.contains(selected) {
            index = selected
        } else {
            guard word != .zero else { return }
            pageStart = 0
            build([StripCell(learned.text)], layout: .row, selected: 0, word: word)
            index = 0
        }
        guard let panel, let strip, let track, let thumb else { return }
        generation += 1
        let current = generation
        settling = true
        shown = nil
        let (said, spoken) = switch learned.learning {
        case .once: (L("Noted"), L("%@ → %@, once", learned.text, learned.language.displayName))
        case .forGood: (L("Learned"), L("%@ → always %@", learned.text, learned.language.displayName))
        case .forgot: (L("Reset"), L("%@, back to Araso's own reading", learned.text))
        }
        root?.setAccessibilityLabel(spoken)
        announce(spoken)

        // Where the capsule goes: under the word's first letter, as wide as what it says. The panel
        // grows to cover it at once, nothing moving on screen, so the views can travel there.
        let cell = cells[index]
        if clip != nil {
            foldCard(onto: cell, said: said, learned, word: word, current: current)
            return fadeSettled(panel, current)
        }
        let start = cell.frame
        let stripOnScreen = NSRect(x: panel.frame.minX + strip.frame.minX, y: panel.frame.minY + margin,
                                   width: strip.frame.width, height: height)
        let width = cell.makeRoom(for: said)
        let from = stripOnScreen.minX + start.minX
        let to = word == .zero ? from : CaretPanel.origin(for: NSSize(width: width, height: height),
                                                          caret: word.offsetBy(dx: -StripCell.pad, dy: 0),
                                                          gap: CaretPanel.indicatorGap, centered: false).x
        let covered = stripOnScreen.union(NSRect(x: min(from, to), y: stripOnScreen.minY, width: abs(to - from) + width, height: height))
            .insetBy(dx: -margin, dy: -margin)
        panel.ignoresMouseEvents = true
        panel.setFrame(covered, display: false)
        // The strip grows too, so the wider capsule isn't cut at its old end.
        strip.frame = NSRect(x: stripOnScreen.minX - covered.minX, y: margin,
                             width: max(strip.frame.width, start.minX + width), height: height)

        // The paper closes onto the chosen reading and goes with the others; the capsule takes
        // over its shadow.
        animate(0.15, ease, {
            track.animator().frame = start
            track.animator().alphaValue = 0
            for other in cells where other !== cell { other.animator().alphaValue = 0 }
            thumb.layer?.shadowOpacity = shadowOpacity(for: thumb)
        })

        // Then it moves under the word and says it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard current == generation else { return }
            animate(0.22, ease, {
                strip.animator().setFrameOrigin(NSPoint(x: strip.frame.minX + to - from, y: margin))
                thumb.animator().frame = NSRect(x: start.minX, y: 0, width: width, height: height)
                cell.dropNumber()
                if learned.learning == .forgot {
                    var gray = Paper.reset.cgColor
                    thumb.effectiveAppearance.performAsCurrentDrawingAppearance { gray = Paper.reset.cgColor }
                    thumb.layer?.backgroundColor = gray
                }
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                guard current == generation else { return }
                cell.say(learned.learning)
            }
        }
        fadeSettled(panel, current)
    }

    /// The card shrinks into the capsule of `cell` under the word, in one move: its paper and the
    /// thumb land on the same frame, the other readings gone early, and the capsule takes over the
    /// shadow as the paper goes.
    private static func foldCard(onto cell: StripCell, said: String, _ learned: InputSession.Learned, word: NSRect, current: Int) {
        guard let panel, let strip, let track, let thumb else { return }
        let card = NSRect(x: panel.frame.minX + strip.frame.minX, y: panel.frame.maxY - strip.frame.minY - track.frame.height,
                          width: track.frame.width, height: track.frame.height)
        let start = cell.convert(cell.bounds, to: strip)
        // The capsule is the row's height: its letters don't change size on the way.
        let height = cell.frame.height
        let width = cell.makeRoom(for: said)
        let to = word == .zero ? card.minX : CaretPanel.origin(for: NSSize(width: width, height: height),
                                                               caret: word.offsetBy(dx: -StripCell.pad, dy: 0),
                                                               gap: CaretPanel.indicatorGap, centered: false).x
        let top = above ? card.height - height : 0
        let covered = card.union(NSRect(x: to, y: card.maxY - top - height, width: width, height: height))
            .insetBy(dx: -margin, dy: -margin)
        panel.ignoresMouseEvents = true
        panel.setFrame(covered, display: false)
        strip.frame = NSRect(x: card.minX - covered.minX, y: margin,
                             width: max(card.width, to - card.minX + width), height: card.height)
        // Out of the rows' clip, which would cut them on the way.
        for view in [thumb, cell] {
            view.removeFromSuperview()
            strip.addSubview(view)
        }
        thumb.frame = start
        cell.setFrameOrigin(start.origin)
        let capsule = NSRect(x: to - card.minX, y: top, width: width, height: height)
        animate(0.1, ease, { for other in cells where other !== cell { other.animator().alphaValue = 0 } })
        if !reduceMotion {
            let round = CABasicAnimation(keyPath: "cornerRadius")
            round.fromValue = track.layer?.cornerRadius
            round.toValue = height / 2
            round.duration = 0.26
            round.timingFunction = ease
            track.layer?.add(round, forKey: "round")
        }
        track.layer?.cornerRadius = height / 2
        animate(0.26, ease, {
            track.animator().frame = capsule
            thumb.animator().frame = capsule
            cell.animator().setFrameOrigin(capsule.origin)
            cell.dropNumber()
            if learned.learning == .forgot {
                var gray = Paper.reset.cgColor
                thumb.effectiveAppearance.performAsCurrentDrawingAppearance { gray = Paper.reset.cgColor }
                thumb.layer?.backgroundColor = gray
            }
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            guard current == generation else { return }
            cell.say(learned.learning)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard current == generation else { return }
            animate(0.08, nil, {
                track.animator().alphaValue = 0
                thumb.layer?.shadowOpacity = shadowOpacity(for: thumb)
            })
        }
    }

    /// What a correction said goes after its moment.
    private static func fadeSettled(_ panel: NSPanel, _ current: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9) {
            guard current == generation else { return }
            animate(0.25, nil, { panel.animator().alphaValue = 0 }) {
                guard current == generation else { return }
                panel.orderOut(nil)
                settling = false
            }
        }
    }

    /// The readings in a row or the candidates in a card, `selected` on the thumb, the first text
    /// under the word's first letter (the clause's, for candidates). A page turned (`turn`, +1
    /// forward) keeps the card where it is and brings the next page up into it (the one before,
    /// down); a new strip or card comes down 2 pt as it shows (up, when it is above the word).
    private static func build(_ cells: [StripCell], layout: Layout, selected: Int, word: NSRect, turn: CGFloat? = nil,
                              unfolds: Bool = false) {
        let wasUp = isUp
        let oldStrip = wasUp ? panel.map { NSPoint(x: $0.frame.minX + margin, y: $0.frame.minY + margin) } : nil
        hiding = false
        let panel = panel ?? CaretPanel.make(size: .zero)
        self.panel = panel
        panel.ignoresMouseEvents = false

        let size: NSSize
        let rowHeight = cells.first?.frame.height ?? height
        var radius = rowHeight / 2
        var clip: NSView?
        var footers: [NSView] = []
        switch layout {
        case .row:
            var x: CGFloat = 0
            for cell in cells {
                cell.setFrameOrigin(NSPoint(x: x, y: 0))
                x += cell.frame.width
            }
            size = NSSize(width: ceil(x), height: height)
        case .card(let width, let rows, let text):
            // The rows inside the paper's inset, cut at its edge, so a page turned slides in under it.
            let inside = FlippedView(frame: NSRect(x: inset, y: inset, width: width - inset * 2, height: CGFloat(rows) * rowHeight))
            inside.wantsLayer = true
            inside.layer?.masksToBounds = true
            inside.layer?.cornerRadius = rowHeight / 2
            inside.layer?.cornerCurve = .continuous
            for (i, cell) in cells.enumerated() {
                cell.frame = NSRect(x: 0, y: CGFloat(i) * rowHeight, width: inside.frame.width, height: rowHeight)
                cell.alignLanguage()
            }
            size = NSSize(width: width, height: inside.frame.maxY + (text == nil ? 0 : footerHeight) + inset)
            // The corners round about the thumb's, the inset further out.
            radius = inset + rowHeight / 2
            clip = inside
            if let text {
                let side = inset + StripCell.pad
                let line = NSView(frame: NSRect(x: side, y: inside.frame.maxY + 3, width: width - side * 2, height: 1))
                line.wantsLayer = true
                line.effectiveAppearance.performAsCurrentDrawingAppearance { line.layer?.backgroundColor = Paper.line.cgColor }
                footers.append(line)
                let label = StripCell.footer(text.reading)
                label.sizeToFit()
                label.setFrameOrigin(NSPoint(x: side, y: line.frame.maxY + 4))
                footers.append(label)
                if let page = text.page {
                    let pageLabel = StripCell.footer(page)
                    pageLabel.sizeToFit()
                    pageLabel.setFrameOrigin(NSPoint(x: width - side - pageLabel.frame.width, y: line.frame.maxY + 4))
                    footers.append(pageLabel)
                }
            }
        }
        // Measured now: once it is the panel's content, the root takes the panel's old size.
        let full = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)

        let root = FlippedView(frame: NSRect(origin: .zero, size: full))
        root.wantsLayer = true
        let strip = FlippedView(frame: NSRect(origin: NSPoint(x: margin, y: margin), size: size))
        strip.wantsLayer = true
        let track = capsule(NSRect(origin: .zero, size: size), radius: radius)
        let thumb = capsule(cells[selected].frame)
        root.effectiveAppearance.performAsCurrentDrawingAppearance {
            track.layer?.backgroundColor = Paper.background.cgColor
            track.layer?.borderColor = Paper.line.cgColor
            track.layer?.borderWidth = 1
            thumb.layer?.backgroundColor = CaretPanel.indicatorFill.cgColor
        }
        track.layer?.shadowOpacity = shadowOpacity(for: root)
        thumb.layer?.shadowOpacity = 0
        strip.addSubview(track)
        // What holds the thumb and the cells: the strip itself, or a card's page in its clip.
        var page: NSView = strip
        if let clip {
            page = FlippedView(frame: clip.bounds)
            page.wantsLayer = true
            clip.addSubview(page)
            strip.addSubview(clip)
        }
        page.addSubview(thumb)
        cells.forEach(page.addSubview)
        page.addSubview(ClickView(frame: page.bounds) { clicked(at: $0) })
        footers.forEach(strip.addSubview)
        root.addSubview(strip)
        root.setAccessibilityRole(.list)
        panel.contentView = root
        self.root = root
        self.strip = strip
        self.track = track
        self.clip = clip
        self.thumb = thumb
        self.cells = cells
        self.selected = selected
        for (i, cell) in cells.enumerated() { cell.color(on: i == selected) }

        let indent = (clip?.frame.minX ?? 0) + (cells.first?.text.frame.minX ?? StripCell.pad)
        var origin = CaretPanel.origin(for: size, caret: word == .zero ? .zero : word.offsetBy(dx: -indent, dy: 0),
                                       gap: CaretPanel.indicatorGap, centered: false)
        if turn != nil, let oldStrip { origin = oldStrip }
        let above = word != .zero && origin.y > word.minY
        self.above = above
        panel.setFrame(NSRect(origin: NSPoint(x: origin.x - margin, y: origin.y - margin), size: full), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if let turn, wasUp {
            let rest = page.frame.origin
            page.alphaValue = 0
            page.setFrameOrigin(NSPoint(x: rest.x, y: rest.y + 14 * turn))
            animate(0.14, ease, {
                page.animator().alphaValue = 1
                page.animator().setFrameOrigin(rest)
            })
        } else if !wasUp, unfolds, !reduceMotion, let clip {
            // The card opens from the chosen row, the others coming a little later the further they are.
            let full = track.frame
            track.frame = cells[selected].frame.offsetBy(dx: clip.frame.minX, dy: clip.frame.minY).insetBy(dx: -inset, dy: -inset)
            root.alphaValue = 0
            animate(0.06, nil, { root.animator().alphaValue = 1 })
            animate(0.2, ease, { track.animator().frame = full })
            for (i, cell) in cells.enumerated() where i != selected {
                cell.wantsLayer = true
                let distance = abs(i - selected)
                let rise = CABasicAnimation(keyPath: "transform.translation.y")
                rise.fromValue = i < selected ? 6 : -6
                rise.toValue = 0
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                for animation in [rise, fade] {
                    animation.duration = 0.18
                    animation.beginTime = CACurrentMediaTime() + 0.025 * Double(distance)
                    animation.fillMode = .backwards
                    animation.timingFunction = ease
                    cell.layer?.add(animation, forKey: animation.keyPath)
                }
            }
        } else if !wasUp {
            root.alphaValue = 0
            strip.setFrameOrigin(NSPoint(x: margin, y: margin + (above ? 2 : -2)))
            animate(0.12, ease, {
                root.animator().alphaValue = 1
                strip.animator().setFrameOrigin(NSPoint(x: margin, y: margin))
            })
        }
    }

    /// A capsule the strip's height (or, `radius` larger, the card), casting the strip's shadow
    /// when it shows one.
    private static func capsule(_ frame: NSRect, radius: CGFloat? = nil) -> NSView {
        let view = NSView(frame: frame)
        view.wantsLayer = true
        view.layer?.cornerRadius = radius ?? frame.height / 2
        view.layer?.cornerCurve = .continuous
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowRadius = 5
        view.layer?.shadowOffset = CGSize(width: 0, height: -3)
        return view
    }

    /// The strip's shadow, deeper on dark paper.
    private static func shadowOpacity(for view: NSView) -> Float {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.45 : 0.14
    }

    /// The next switch or candidate: the thumb moves to it.
    private static func select(_ index: Int) {
        guard cells.indices.contains(index), let thumb else { return }
        selected = index
        animate(0.12, ease, { thumb.animator().frame = cells[index].frame })
        for (i, cell) in cells.enumerated() { cell.color(on: i == index) }
    }

    /// `point` is in the cells' view: on a reading or a candidate, or between the last one and the
    /// card's end, where nothing is.
    private static func clicked(at point: NSPoint) {
        guard !settling, let index = cells.firstIndex(where: { $0.frame.contains(point) }) else { return }
        if let choose {
            choose(pageStart + index)
        } else if let pick, languages.indices.contains(index) {
            pick(languages[index])
        }
    }

    /// Read out by VoiceOver.
    private static func announce(_ text: String) {
        guard let panel else { return }
        NSAccessibility.post(element: panel, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

/// Takes a click on the strip (the panel never takes focus) and says where, top-down.
private final class ClickView: NSView {
    private let clicked: (NSPoint) -> Void
    init(frame: NSRect, clicked: @escaping (NSPoint) -> Void) {
        self.clicked = clicked
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { clicked(convert(event.locationInWindow, from: nil)) }
}
