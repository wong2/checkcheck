import AppKit

private let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

private func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

private func gradient(_ colors: [CGColor], locations: [CGFloat]) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: colors as CFArray,
        locations: locations
    )!
}

private func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics

    let context = graphics.cgContext
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let scale = CGFloat(size) / 1024
    context.scaleBy(x: scale, y: scale)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let tileRect = CGRect(x: 72, y: 54, width: 880, height: 880)
    let tilePath = CGPath(roundedRect: tileRect, cornerWidth: 214, cornerHeight: 214, transform: nil)

    context.addPath(tilePath)
    context.setFillColor(color(18, 23, 29))
    context.fillPath()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    context.drawLinearGradient(
        gradient(
            [color(45, 52, 63), color(26, 32, 40), color(16, 20, 25)],
            locations: [0, 0.52, 1]
        ),
        start: CGPoint(x: 170, y: 900),
        end: CGPoint(x: 850, y: 100),
        options: []
    )
    context.drawRadialGradient(
        gradient([color(34, 197, 94, 0.20), color(34, 197, 94, 0)], locations: [0, 1]),
        startCenter: CGPoint(x: 650, y: 464),
        startRadius: 0,
        endCenter: CGPoint(x: 650, y: 464),
        endRadius: 410,
        options: []
    )
    context.restoreGState()

    context.addPath(tilePath)
    context.setStrokeColor(color(255, 255, 255, 0.16))
    context.setLineWidth(3)
    context.strokePath()

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 28, color: color(0, 0, 0, 0.30))
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(88)

    context.beginPath()
    context.move(to: CGPoint(x: 235, y: 524))
    context.addLine(to: CGPoint(x: 382, y: 377))
    context.addLine(to: CGPoint(x: 696, y: 691))
    context.setStrokeColor(color(136, 147, 162, 0.72))
    context.strokePath()

    context.beginPath()
    context.move(to: CGPoint(x: 350, y: 524))
    context.addLine(to: CGPoint(x: 497, y: 377))
    context.addLine(to: CGPoint(x: 811, y: 691))
    context.setStrokeColor(color(67, 226, 112))
    context.strokePath()
    context.restoreGState()

    context.setFillColor(color(115, 244, 154, 0.88))
    context.fillEllipse(in: CGRect(x: 813, y: 810, width: 36, height: 36))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: swift Artwork/generate_icon.swift <appiconset-directory>")
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
for (name, size) in outputs {
    try render(size: size).write(to: outputDirectory.appendingPathComponent(name))
}
