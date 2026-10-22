// Renders the Kyōmei app icon (1024 px PNG): ink-black squircle, hand-drawn resonance rings
// around an earbud, and a red 共鳴 seal, in Kakushin's sketched style.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "icon.png"
let size: CGFloat = 1024

/// Deterministic jitter so every build draws the same "hand".
struct Pen {
    var state: UInt64 = 0x9E37_79B9_7F4A_7C15
    mutating func next() -> CGFloat {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return CGFloat(Double(state >> 33) / Double(1 << 31)) - 0.5
    }
}
var pen = Pen()

/// A wobbly circle, drawn twice like a quick pen sketch.
func sketchCircle(center c: CGPoint, radius r: CGFloat, from: CGFloat = 0, to: CGFloat = 2 * .pi, width: CGFloat) {
    for pass in 0..<2 {
        let path = NSBezierPath()
        let steps = 64
        let drift = pen.next() * r * 0.03
        for i in 0...steps {
            let t = from + (to - from) * CGFloat(i) / CGFloat(steps)
            let wobble = r * 0.012 * sin(t * 3 + CGFloat(pass)) + pen.next() * r * 0.008 + drift
            let p = CGPoint(x: c.x + (r + wobble) * cos(t), y: c.y + (r + wobble) * sin(t))
            i == 0 ? path.move(to: p) : path.line(to: p)
        }
        path.lineWidth = width * (pass == 0 ? 1 : 0.55)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(pass == 0 ? 0.95 : 0.55).setStroke()
        path.stroke()
    }
}

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Squircle on Apple's icon grid.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let squircle = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor(white: 0.04, alpha: 1).setFill()
squircle.fill()
NSGraphicsContext.current?.restoreGraphicsState()

NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()
// Faint paper grain so the black reads as ink, not plastic.
for _ in 0..<1400 {
    let x = rect.minX + (pen.next() + 0.5) * rect.width
    let y = rect.minY + (pen.next() + 0.5) * rect.height
    NSColor.white.withAlphaComponent(0.035).setFill()
    NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 2, height: 2)).fill()
}

let center = CGPoint(x: size * 0.44, y: size * 0.54)
// Resonance: rings opening to the upper right, toward "the Mac".
sketchCircle(center: center, radius: 120, width: 18)
sketchCircle(center: center, radius: 205, from: -0.95, to: 1.55, width: 15)
sketchCircle(center: center, radius: 290, from: -0.75, to: 1.35, width: 12)
sketchCircle(center: center, radius: 372, from: -0.55, to: 1.1, width: 9)

// Earbud glyph in the middle.
let config = NSImage.SymbolConfiguration(pointSize: 150, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let bud = NSImage(systemSymbolName: "airpod.left", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let s = bud.size
    bud.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
}

// 共鳴 seal, bottom right, slightly rotated, hatched like a worn stamp.
let ink = NSColor(red: 0.784, green: 0.063, blue: 0.180, alpha: 1)
NSGraphicsContext.current?.saveGraphicsState()
let transform = NSAffineTransform()
transform.translateX(by: size * 0.70, yBy: size * 0.25)
transform.rotate(byDegrees: -7)
transform.concat()
let seal = NSRect(x: -112, y: -112, width: 224, height: 224)
let frame = NSBezierPath(roundedRect: seal, xRadius: 10, yRadius: 10)
frame.lineWidth = 12
ink.setStroke()
frame.stroke()
NSGraphicsContext.current?.saveGraphicsState()
frame.addClip()
for i in stride(from: -260, through: 260, by: 26) {
    let hatch = NSBezierPath()
    hatch.move(to: CGPoint(x: CGFloat(i) - 120, y: -130))
    hatch.line(to: CGPoint(x: CGFloat(i) + 120, y: 130))
    hatch.lineWidth = 3
    ink.withAlphaComponent(0.35).setStroke()
    hatch.stroke()
}
NSGraphicsContext.current?.restoreGraphicsState()
let font = NSFont(name: "HiraMinProN-W6", size: 92) ?? NSFont.systemFont(ofSize: 92, weight: .bold)
let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink]
for (i, glyph) in ["共", "鳴"].enumerated() {
    let text = NSAttributedString(string: glyph, attributes: attributes)
    let t = text.size()
    text.draw(at: CGPoint(x: -t.width / 2, y: (i == 0 ? 2 : -t.height + 6)))
}
NSGraphicsContext.current?.restoreGraphicsState()
NSGraphicsContext.current?.restoreGraphicsState()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
