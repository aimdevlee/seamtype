// Draws the menu-bar input source icon: A, 아 and あ (all read "a") drawn at one spot and cut
// into rows, one per language: the top of A, the middle of 아, the bottom of あ. One icon
// whatever is switched on: the bundle is signed, so it can't change at runtime.
// Black on transparent, so macOS can tint it (TISIconIsTemplate), at 1x and 2x in one TIFF.
// usage: swift scripts/make-icon.swift <out.tiff>
import AppKit
import CoreText

let out = URL(fileURLWithPath: CommandLine.arguments.last!)
let W: CGFloat = 20, H: CGFloat = 16

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> CTFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
    return (NSFont(descriptor: descriptor, size: size) ?? base) as CTFont
}

/// Outline of `text` centred on (cx, cy), y measured from the top. Each run uses its own
/// (fallback) font, so 가 and あ get real Hangul and kana outlines.
func glyphPath(_ text: String, size: CGFloat, cx: CGFloat, cy: CGFloat) -> CGPath {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: roundedFont(size, .heavy)]))
    let path = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(), &glyphs)
        CTRunGetPositions(run, CFRange(), &positions)
        let font = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName as String] as! CTFont
        for i in 0..<count {
            if let g = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                path.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
    }
    let box = path.boundingBoxOfPath
    var move = CGAffineTransform(translationX: cx - box.midX, y: (H - cy) - box.midY)
    return path.copy(using: &move)!
}

/// One row per language, top to bottom, at one spot: each row shows only its own letter, so the
/// top of A runs into the middle of 아 and the bottom of あ.
struct Mark {
    /// (letter, font size), top row first.
    let letters: [(String, CGFloat)]
}

let mark = Mark(letters: [("A", 18), ("아", 17), ("あ", 17)])
/// Clear space between rows.
let gap: CGFloat = 1

func representation(_ mark: Mark, scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    let c = context.cgContext
    c.setFillColor(NSColor.black.cgColor)

    let rows = CGFloat(mark.letters.count)
    for (i, (text, size)) in mark.letters.enumerated() {
        // Row edges measured from the top; the gap is split between neighbouring rows.
        let top = H * CGFloat(i) / rows + (i == 0 ? 0 : gap / 2)
        let bottom = H * CGFloat(i + 1) / rows - (i == mark.letters.count - 1 ? 0 : gap / 2)
        c.saveGState()
        c.clip(to: CGRect(x: 0, y: H - bottom, width: W, height: bottom - top))
        c.addPath(glyphPath(text, size: size, cx: W / 2, cy: H / 2)); c.fillPath()
        c.restoreGState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let image = NSImage(size: NSSize(width: W, height: H))
image.addRepresentation(representation(mark, scale: 1))
image.addRepresentation(representation(mark, scale: 2))
try! image.tiffRepresentation!.write(to: out)
