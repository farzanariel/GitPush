import AppKit
import Foundation

struct Palette {
    static let backgroundTop = NSColor(calibratedRed: 0.07, green: 0.11, blue: 0.20, alpha: 1.0)
    static let backgroundBottom = NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.13, alpha: 1.0)
    static let glow = NSColor(calibratedRed: 0.10, green: 0.66, blue: 0.74, alpha: 0.35)
    static let branch = NSColor(calibratedRed: 1.00, green: 0.45, blue: 0.33, alpha: 1.0)
    static let branchShade = NSColor(calibratedRed: 0.84, green: 0.28, blue: 0.21, alpha: 1.0)
    static let arrow = NSColor(calibratedRed: 0.56, green: 0.96, blue: 0.86, alpha: 1.0)
    static let arrowShade = NSColor(calibratedRed: 0.26, green: 0.84, blue: 0.74, alpha: 1.0)
    static let highlight = NSColor(calibratedWhite: 1.0, alpha: 0.16)
    static let shadow = NSColor(calibratedWhite: 0.0, alpha: 0.22)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let sizes = [16, 32, 64, 128, 256, 512, 1024]

func fillRoundedRect(_ rect: NSRect, radius: CGFloat, gradientColors: [NSColor], locations: [CGFloat], angle: CGFloat) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    path.addClip()
    let gradient = NSGradient(colors: gradientColors, atLocations: locations, colorSpace: .deviceRGB)!
    gradient.draw(in: path, angle: angle)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let cornerRadius = size * 0.225

    fillRoundedRect(
        rect,
        radius: cornerRadius,
        gradientColors: [Palette.backgroundTop, Palette.backgroundBottom],
        locations: [0.0, 1.0],
        angle: -90
    )

    let glowRect = NSRect(x: size * 0.12, y: size * 0.48, width: size * 0.9, height: size * 0.48)
    let glowPath = NSBezierPath(ovalIn: glowRect)
    glowPath.addClip()
    let glowGradient = NSGradient(colors: [Palette.glow, .clear])!
    glowGradient.draw(in: glowPath, relativeCenterPosition: NSPoint(x: -0.15, y: 0.1))

    let topHighlight = NSBezierPath(roundedRect: NSRect(x: size * 0.07, y: size * 0.62, width: size * 0.86, height: size * 0.23), xRadius: size * 0.16, yRadius: size * 0.16)
    Palette.highlight.setFill()
    topHighlight.fill()

    let motifShadow = NSShadow()
    motifShadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
    motifShadow.shadowBlurRadius = size * 0.04
    motifShadow.shadowColor = Palette.shadow
    motifShadow.set()

    let branchLineWidth = max(size * 0.11, 2.4)
    let branchCapRadius = max(size * 0.09, 2.6)

    let left = NSPoint(x: size * 0.30, y: size * 0.33)
    let middle = NSPoint(x: size * 0.50, y: size * 0.33)
    let top = NSPoint(x: size * 0.50, y: size * 0.67)

    let branchPath = NSBezierPath()
    branchPath.lineCapStyle = .round
    branchPath.lineJoinStyle = .round
    branchPath.lineWidth = branchLineWidth
    branchPath.move(to: left)
    branchPath.line(to: middle)
    branchPath.line(to: top)
    Palette.branchShade.setStroke()
    branchPath.stroke()

    NSGraphicsContext.current?.saveGraphicsState()
    let branchClip = branchPath.copy() as! NSBezierPath
    branchClip.lineWidth = branchLineWidth
    branchClip.addClip()
    let branchGradientRect = NSRect(x: size * 0.2, y: size * 0.2, width: size * 0.5, height: size * 0.55)
    let branchGradient = NSGradient(colors: [Palette.branch, Palette.branchShade])!
    branchGradient.draw(in: branchGradientRect, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    for point in [left, middle, top] {
        let nodeRect = NSRect(x: point.x - branchCapRadius, y: point.y - branchCapRadius, width: branchCapRadius * 2, height: branchCapRadius * 2)
        let nodePath = NSBezierPath(ovalIn: nodeRect)
        Palette.branchShade.setFill()
        nodePath.fill()

        NSGraphicsContext.current?.saveGraphicsState()
        nodePath.addClip()
        let nodeGradient = NSGradient(colors: [Palette.branch, Palette.branchShade])!
        nodeGradient.draw(in: nodeRect, angle: -90)
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    NSGraphicsContext.current?.restoreGraphicsState()

    let arrowLineWidth = max(size * 0.125, 2.8)
    let arrowStart = NSPoint(x: size * 0.58, y: size * 0.42)
    let arrowEnd = NSPoint(x: size * 0.76, y: size * 0.71)
    let arrowTipLeft = NSPoint(x: size * 0.64, y: size * 0.69)
    let arrowTipRight = NSPoint(x: size * 0.80, y: size * 0.60)

    let arrowShaft = NSBezierPath()
    arrowShaft.lineCapStyle = .round
    arrowShaft.lineJoinStyle = .round
    arrowShaft.lineWidth = arrowLineWidth
    arrowShaft.move(to: arrowStart)
    arrowShaft.line(to: arrowEnd)
    Palette.arrowShade.setStroke()
    arrowShaft.stroke()

    NSGraphicsContext.current?.saveGraphicsState()
    let arrowClip = arrowShaft.copy() as! NSBezierPath
    arrowClip.lineWidth = arrowLineWidth
    arrowClip.addClip()
    let arrowGradient = NSGradient(colors: [Palette.arrow, Palette.arrowShade])!
    arrowGradient.draw(in: NSRect(x: size * 0.52, y: size * 0.35, width: size * 0.33, height: size * 0.42), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let arrowHead = NSBezierPath()
    arrowHead.lineCapStyle = .round
    arrowHead.lineJoinStyle = .round
    arrowHead.lineWidth = arrowLineWidth * 0.72
    arrowHead.move(to: arrowTipLeft)
    arrowHead.line(to: arrowEnd)
    arrowHead.line(to: arrowTipRight)
    Palette.arrowShade.setStroke()
    arrowHead.stroke()

    NSGraphicsContext.current?.saveGraphicsState()
    let headClip = arrowHead.copy() as! NSBezierPath
    headClip.lineWidth = arrowLineWidth * 0.72
    headClip.addClip()
    let headGradient = NSGradient(colors: [Palette.arrow, Palette.arrowShade])!
    headGradient.draw(in: NSRect(x: size * 0.58, y: size * 0.56, width: size * 0.24, height: size * 0.18), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    let accentRect = NSRect(x: size * 0.18, y: size * 0.18, width: size * 0.64, height: size * 0.64)
    let accentPath = NSBezierPath(roundedRect: accentRect, xRadius: size * 0.17, yRadius: size * 0.17)
    accentPath.lineWidth = max(size * 0.012, 1.0)
    NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
    accentPath.stroke()

    image.unlockFocus()
    return image
}

func writePNG(image: NSImage, pixelSize: Int, to url: URL) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap"])
    }

    bitmap.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        throw NSError(domain: "IconGeneration", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create graphics context"])
    }

    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGeneration", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to build PNG data"])
    }

    try png.write(to: url)
}

do {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

    for size in sizes {
        let image = drawIcon(size: CGFloat(size))
        try writePNG(image: image, pixelSize: size, to: outputDirectory.appendingPathComponent("appicon_\(size).png"))
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
