// Renders assets/dmg-background.tiff (1x + 2x) for the installer window:
// app on the left, arrow, Applications on the right (positions match scripts/build-app.sh).
//   swift scripts/make-dmg-background.swift
import AppKit

let width: CGFloat = 640, height: CGFloat = 400

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let px = Int(width * scale), py = Int(height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: py, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext  // already in points: rep.size maps them to pixels
    // Flip to top-left origin, like Finder's icon positions.
    ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1)

    // Light warm ground (design system light theme) so Finder's black labels stay legible.
    let grad = CGGradient(colorsSpace: nil, colors: [color(0xfbfaf7), color(0xeeece7)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: 0, y: height), options: [])

    // Arrow from the app slot (x 170) to Applications (x 470), at icon height (y 180).
    let y: CGFloat = 180
    ctx.setStrokeColor(color(0x8f897f)); ctx.setLineWidth(5); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setLineDash(phase: 0, lengths: [0.01, 14])
    ctx.move(to: CGPoint(x: 262, y: y)); ctx.addLine(to: CGPoint(x: 362, y: y)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    ctx.move(to: CGPoint(x: 360, y: y - 16)); ctx.addLine(to: CGPoint(x: 378, y: y)); ctx.addLine(to: CGPoint(x: 360, y: y + 16))
    ctx.strokePath()

    // Caption (drawn unflipped).
    ctx.translateBy(x: 0, y: height); ctx.scaleBy(x: 1, y: -1)
    let text = NSAttributedString(string: "Arraste o VibeDeck para Aplicações", attributes: [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium),
        .foregroundColor: NSColor(cgColor: color(0x625d55))!,
    ])
    let size = text.size()
    text.draw(at: NSPoint(x: (width - size.width) / 2, y: 64))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let tmp = FileManager.default.temporaryDirectory
let one = tmp.appending(path: "dmg-background.png"), two = tmp.appending(path: "dmg-background@2x.png")
try render(scale: 1).representation(using: .png, properties: [:])!.write(to: one)
try render(scale: 2).representation(using: .png, properties: [:])!.write(to: two)
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/tiffutil")
p.arguments = ["-cathidpicheck", one.path, two.path, "-out", root.appending(path: "assets/dmg-background.tiff").path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ assets/dmg-background.tiff" : "tiffutil failed")
exit(p.terminationStatus)
