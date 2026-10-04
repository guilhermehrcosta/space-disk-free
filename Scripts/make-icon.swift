// Gera Resources/AppIcon.icns desenhando o ícone com AppKit.
// Uso: swift Scripts/make-icon.swift   (ou `make icon`)
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, colors: [NSColor]) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(NSImage.SymbolConfiguration(paletteColors: colors))
    guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
        fatalError("SF Symbol não encontrado: \(name)")
    }
    return image
}

func draw(_ image: NSImage, centeredAt center: NSPoint) {
    let size = image.size
    image.draw(in: NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height))
}

/// Desenha o ícone num espaço de 1024×1024 pontos, seguindo a grade de ícones do macOS
/// (corpo de 824 pt centralizado, cantos arredondados e sombra suave).
func drawIcon() {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 24
    shadow.shadowColor = color(0x000000, alpha: 0.35)
    shadow.set()
    color(0x1E3A8A).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [color(0x38BDF8), color(0x2563EB), color(0x312E81)])!
        .draw(in: shape, angle: -90)

    // Brilho sutil na metade de cima.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSGradient(colors: [color(0xFFFFFF, alpha: 0.18), color(0xFFFFFF, alpha: 0)])!
        .draw(in: NSRect(x: body.minX, y: body.midY, width: body.width, height: body.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Anel de uso do disco: trilho translúcido e arco preenchido.
    let center = NSPoint(x: canvas / 2, y: canvas / 2 - 6)
    let radius: CGFloat = 268
    let lineWidth: CGFloat = 58

    let track = NSBezierPath()
    track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
    track.lineWidth = lineWidth
    color(0xFFFFFF, alpha: 0.22).setStroke()
    track.stroke()

    let used = NSBezierPath()
    used.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 250, clockwise: true)
    used.lineWidth = lineWidth
    used.lineCapStyle = .round
    color(0xFFFFFF).setStroke()
    used.stroke()

    draw(symbol("internaldrive.fill", pointSize: 230, weight: .semibold, colors: [.white]), centeredAt: center)

    // Brilho de "limpo" sobre o anel, no canto superior direito.
    draw(
        symbol("sparkle", pointSize: 150, weight: .bold, colors: [color(0xFDE68A)]),
        centeredAt: NSPoint(x: center.x + radius * 0.72, y: center.y + radius * 0.72)
    )
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: canvas, height: canvas)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try png(pixels: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
    try png(pixels: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let output = root.appending(path: "Resources/AppIcon.icns")
let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil falhou") }

// Prévia em PNG para revisar o desenho sem abrir o .icns.
if let preview = ProcessInfo.processInfo.environment["ICON_PREVIEW"] {
    try png(pixels: 1024).write(to: URL(filePath: preview))
}
print("✓ \(output.path)")
