// Renders assets/AppIcon.icns from the VibeDeck mark (design system "Logo"):
// two cards fanned into a V — front = human (tangerina), back = AI (lagoa) — on the dark tile.
//   swift scripts/make-icon.swift
import AppKit

let markBack = "M44.20 12.79 L43.74 12.63 L43.26 12.51 L42.78 12.44 L42.29 12.42 L41.80 12.45 L41.31 12.53 L40.84 12.65 L40.38 12.82 L39.93 13.04 L39.52 13.29 L39.12 13.59 L38.76 13.92 L38.44 14.29 L38.15 14.68 L37.90 15.11 L37.69 15.55 L33.62 25.64 L40.33 42.24 L40.38 42.38 L40.54 42.84 L40.62 43.13 L40.74 43.60 L40.79 43.89 L40.86 44.38 L40.89 44.67 L40.91 45.16 L40.90 45.46 L40.87 45.95 L40.84 46.24 L40.77 46.72 L40.71 47.01 L40.58 47.49 L40.50 47.77 L40.33 48.23 L40.21 48.50 L40.00 48.94 L39.86 49.20 L39.60 49.62 L39.44 49.86 L39.14 50.25 L38.95 50.48 L38.62 50.84 L38.41 51.05 L38.04 51.37 L37.81 51.56 L37.42 51.85 L37.17 52.01 L36.75 52.26 L36.49 52.39 L36.32 52.47 L36.70 52.49 L37.19 52.46 L37.67 52.38 L38.15 52.26 L38.61 52.09 L39.05 51.88 L39.47 51.62 L39.86 51.33 L40.22 50.99 L40.55 50.63 L40.84 50.23 L41.08 49.81 L41.29 49.36 L52.53 21.55 L52.69 21.08 L52.81 20.61 L52.87 20.12 L52.89 19.63 L52.86 19.14 L52.79 18.65 L52.66 18.18 L52.50 17.72 L52.28 17.28 L52.03 16.86 L51.73 16.47 L51.40 16.11 L51.03 15.78 L50.63 15.49 L50.21 15.24 L49.77 15.04 Z"
let markFront = "M19.80 12.79 L14.23 15.04 L13.79 15.24 L13.37 15.49 L12.97 15.78 L12.60 16.11 L12.27 16.47 L11.97 16.86 L11.72 17.28 L11.50 17.72 L11.34 18.18 L11.21 18.65 L11.14 19.14 L11.11 19.63 L11.13 20.12 L11.19 20.61 L11.31 21.08 L11.47 21.55 L22.71 49.36 L22.92 49.81 L23.16 50.23 L23.45 50.63 L23.78 50.99 L24.14 51.33 L24.53 51.62 L24.95 51.88 L25.39 52.09 L25.85 52.26 L26.33 52.38 L26.81 52.46 L27.30 52.49 L27.79 52.47 L28.28 52.40 L28.76 52.29 L29.22 52.12 L34.78 49.88 L35.23 49.67 L35.65 49.42 L36.05 49.13 L36.41 48.81 L36.75 48.45 L37.04 48.05 L37.30 47.64 L37.51 47.19 L37.68 46.73 L37.80 46.26 L37.88 45.77 L37.91 45.28 L37.89 44.79 L37.82 44.31 L37.71 43.83 L37.54 43.37 L26.31 15.55 L26.10 15.11 L25.85 14.68 L25.56 14.29 L25.24 13.92 L24.88 13.59 L24.48 13.29 L24.07 13.04 L23.62 12.82 L23.16 12.65 L22.69 12.53 L22.20 12.45 L21.71 12.42 L21.22 12.44 L20.74 12.51 L20.26 12.63 Z"

/// The marks are polylines only (M/L/Z), in a 64×64 SVG space (y down).
func cgPath(_ d: String, origin: CGPoint, scale: CGFloat, canvas: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let tokens = d.split(separator: " ")
    var i = 0
    while i < tokens.count {
        let t = tokens[i]
        if t == "Z" { path.closeSubpath(); i += 1; continue }
        let cmd = t.first!
        let x = CGFloat(Double(t.dropFirst())!), y = CGFloat(Double(tokens[i + 1])!)
        let p = CGPoint(x: origin.x + x * scale, y: canvas - (origin.y + y * scale))
        if cmd == "M" { path.move(to: p) } else { path.addLine(to: p) }
        i += 2
    }
    return path
}

func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func render(size px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let k = s / 1024
    // Apple's macOS icon grid: 824pt tile centered on a 1024 canvas, ~185pt continuous corners.
    let tile = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 28 * k, color: CGColor(gray: 0, alpha: 0.45))
    ctx.addPath(shape); ctx.setFillColor(color(0x1b1a19)); ctx.fillPath()
    ctx.restoreGState()

    // Subtle top light + hairline, so the dark tile reads on dark Docks.
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    let grad = CGGradient(colorsSpace: nil, colors: [CGColor(gray: 1, alpha: 0.07), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.midY), options: [])
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1 * k, dy: 1 * k), cornerWidth: 184 * k, cornerHeight: 184 * k, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.10)); ctx.setLineWidth(2 * k); ctx.strokePath()

    // Mark at 64/104 of the tile, as on the design board.
    let markSize = 824 * k * 64 / 104
    let origin = CGPoint(x: (s - markSize) / 2, y: (s - markSize) / 2)
    let unit = markSize / 64
    ctx.addPath(cgPath(markBack, origin: origin, scale: unit, canvas: s)); ctx.setFillColor(color(0x3cc8c0)); ctx.fillPath()
    ctx.addPath(cgPath(markFront, origin: origin, scale: unit, canvas: s)); ctx.setFillColor(color(0xff8a3d)); ctx.fillPath()

    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = fm.temporaryDirectory.appending(path: "AppIcon.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: root.appending(path: "assets/AppIcon.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", root.appending(path: "assets/AppIcon.icns").path]
try p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "✓ assets/AppIcon.icns" : "iconutil failed")
exit(p.terminationStatus)
