import Cocoa

/// A white A shown for a moment under the caret when Araso pauses (struck through, on gray) or
/// resumes in a text field (on the accent color). The menu bar icon can't show it (the bundle is
/// signed, so the icon is fixed). It looks like the system's own input source indicator (macOS 26
/// and later), centered under the caret; the joined mark doesn't read at this size.
@MainActor enum PauseHUD {
    private static var panel: NSPanel?
    private static var imageView: NSImageView?
    /// Bumped on every show, so an older fade-out leaves a newer icon alone.
    private static var shown = 0

    /// The system indicator's capsule.
    private static let size = NSSize(width: 30, height: CaretPanel.indicatorHeight)

    private static let icons = (on: letter(slashed: false), paused: letter(slashed: true))

    /// The A, black to be tinted; the stroke through it has a clear gap cut around it, so it stands
    /// apart from the letter.
    private static func letter(slashed: Bool) -> NSImage {
        let side = NSSize(width: 16, height: 16)
        let image = NSImage(size: side, flipped: false) { rect in
            let base = NSFont.systemFont(ofSize: 14, weight: .heavy)
            let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 14) } ?? base
            let text = NSAttributedString(string: "A", attributes: [.font: font, .foregroundColor: NSColor.black])
            let size = text.size()
            text.draw(at: NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2))
            if slashed, let context = NSGraphicsContext.current?.cgContext {
                let from = CGPoint(x: 2, y: rect.height - 2), to = CGPoint(x: rect.width - 2, y: 2)
                context.setLineCap(.round)
                context.setBlendMode(.clear)
                context.setLineWidth(3.2)
                context.move(to: from); context.addLine(to: to); context.strokePath()
                context.setBlendMode(.normal)
                context.setStrokeColor(NSColor.black.cgColor)
                context.setLineWidth(1.4)
                context.move(to: from); context.addLine(to: to); context.strokePath()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// `caret` is the caret's line in screen coordinates, or `.zero` when the app doesn't say.
    static func show(paused: Bool, caret: NSRect) {
        let (panel, imageView) = make()
        imageView.image = paused ? icons.paused : icons.on
        imageView.setAccessibilityLabel(paused ? L("Araso paused") : L("Araso resumed"))
        var fill = paused ? Paper.reset.cgColor : CaretPanel.indicatorFill.cgColor
        panel.contentView?.effectiveAppearance.performAsCurrentDrawingAppearance {
            fill = paused ? Paper.reset.cgColor : CaretPanel.indicatorFill.cgColor
        }
        panel.contentView?.layer?.backgroundColor = fill
        panel.setFrame(NSRect(origin: CaretPanel.origin(for: size, caret: caret, gap: CaretPanel.indicatorGap, centered: true), size: size),
                       display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        shown += 1
        let current = shown
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            guard current == shown else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) {
                MainActor.assumeIsolated { if current == shown { panel.orderOut(nil) } }
            }
        }
    }

    private static func make() -> (NSPanel, NSImageView) {
        if let panel, let imageView { return (panel, imageView) }
        let panel = CaretPanel.make(size: size)

        let capsule = NSView()
        capsule.wantsLayer = true
        capsule.layer?.cornerRadius = size.height / 2
        capsule.layer?.cornerCurve = .continuous

        let imageView = NSImageView()
        imageView.contentTintColor = .white
        imageView.imageScaling = .scaleNone
        imageView.translatesAutoresizingMaskIntoConstraints = false
        capsule.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: capsule.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: capsule.centerYAnchor),
        ])
        panel.contentView = capsule
        self.panel = panel
        self.imageView = imageView
        return (panel, imageView)
    }
}
