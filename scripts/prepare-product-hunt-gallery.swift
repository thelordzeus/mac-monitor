// Product Hunt stills only. Layouts use unmodified crops of real app captures.
// swift scripts/prepare-product-hunt-gallery.swift <capture-directory> <output-directory>
import AppKit
import CoreText
import Foundation

guard CommandLine.arguments.count == 3 else {
    fatalError("Provide a capture directory and an output directory")
}
let captures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let source = output.appendingPathComponent("source/2026-11-02", isDirectory: true)
try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
let canvas = NSSize(width: 1270, height: 760)
let scale: CGFloat = 2
let ink = NSColor(srgbRed: 0.965, green: 0.973, blue: 0.99, alpha: 1)
let muted = NSColor(srgbRed: 0.62, green: 0.66, blue: 0.73, alpha: 1)
let blue = NSColor(srgbRed: 0.36, green: 0.62, blue: 1, alpha: 1)
let mint = NSColor(srgbRed: 0.30, green: 0.86, blue: 0.71, alpha: 1)
let violet = NSColor(srgbRed: 0.66, green: 0.56, blue: 1, alpha: 1)
let icon = NSImage(contentsOfFile: "Resources/AppIcon.iconset/icon_512x512@2x.png")!

func rect(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: x, y: canvas.height - top - height, width: width, height: height)
}
func text(_ value: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
          color: NSColor = ink, weight: NSFont.Weight = .regular,
          width: CGFloat = 1166, tracking: CGFloat = 0) {
    let font = NSFont.systemFont(ofSize: size, weight: weight)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        NSAttributedString.Key(kCTKernAttributeName as String): tracking,
    ]))
    precondition(CTLineGetTypographicBounds(line, nil, nil, nil) <= Double(width + 1), "Text overflow: \(value)")
    let context = NSGraphicsContext.current!.cgContext
    context.saveGState()
    context.textMatrix = .identity
    context.textPosition = CGPoint(x: x, y: canvas.height - y - font.ascender)
    CTLineDraw(line, context)
    context.restoreGState()
}
func round(_ area: NSRect, radius: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: area, xRadius: radius, yRadius: radius).fill()
}
func glow(_ color: NSColor, _ center: NSPoint, radius: CGFloat) {
    let gradient = NSGradient(colorsAndLocations:
        (color.withAlphaComponent(0.17), 0),
        (color.withAlphaComponent(0.055), 0.55),
        (color.withAlphaComponent(0), 1))!
    gradient.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}
func background(accent: NSColor, section: String) {
    NSColor(srgbRed: 0.035, green: 0.047, blue: 0.065, alpha: 1).setFill()
    NSRect(origin: .zero, size: canvas).fill()
    glow(accent, NSPoint(x: 1080, y: 220), radius: 750)
    glow(blue, NSPoint(x: 100, y: 200), radius: 620)
    icon.draw(in: rect(52, 37, 36, 36))
    text("Mac Pulse", 101, 40, 24, weight: .semibold, width: 350, tracking: -0.5)
    text(section.uppercased(), 999, 48, 12, color: accent,
         weight: .semibold, width: 220, tracking: 2)
}
func pill(_ value: String, x: CGFloat, y: CGFloat, accent: NSColor) {
    let font = NSFont.systemFont(ofSize: 13, weight: .medium)
    let w = (value as NSString).size(withAttributes: [.font: font]).width + 28
    let area = rect(x, y, w, 30)
    round(area, radius: 15, color: accent.withAlphaComponent(0.09))
    text(value, x + 14, y + 6, 13, color: accent, weight: .medium, width: w)
}
var shots: [String: NSImage] = [:]
for name in ["overview", "inventory-caches", "cpu"] {
    guard let bitmap = NSBitmapImageRep(data: try Data(contentsOf: captures.appendingPathComponent(name + ".png"))),
          let cg = bitmap.cgImage else { fatalError("Invalid capture: \(name)") }
    guard cg.width == 3162 && cg.height == 1586 else {
        fatalError("Recrop this layout for the new capture dimensions: \(name) \(cg.width)x\(cg.height)")
    }
    let normalized = NSBitmapImageRep(cgImage: cg)
    try normalized.representation(using: .png, properties: [:])!.write(to: source.appendingPathComponent(name + ".png"))
    // Source crop coordinates below use the app's 1581x793 logical point size.
    shots[name] = NSImage(cgImage: cg, size: NSSize(width: 1581, height: 793))
}
func shot(_ name: String, crop: NSRect, at area: NSRect, radius: CGFloat = 18) {
    let shape = NSBezierPath(roundedRect: area, xRadius: radius, yRadius: radius)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.65)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -16)
    shadow.set()
    NSColor.black.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    shots[name]!.draw(in: area, from: NSRect(x: crop.minX, y: 793 - crop.maxY,
        width: crop.width, height: crop.height), operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.13).setStroke()
    shape.lineWidth = 0.8; shape.stroke()
}
func render(_ file: String, draw: () -> Void) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: Int(canvas.width * scale * 4), bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: scale, y: scale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(file))
    print("Created \(file): 2540x1520")
}

try render("01-monitoring.png") {
    background(accent: blue, section: "Live monitoring")
    text("Your Mac. In the clear.", 52, 99, 62, weight: .bold, tracking: -2)
    text("Live system stats, app activity and storage tools. One native Mac app.",
         54, 178, 20, color: muted)
    // The first two dashboard rows, including the real navigation. No invented readings.
    shot("overview", crop: NSRect(x: 0, y: 0, width: 1581, height: 598),
         at: rect(43, 235, 1184, 448))
    pill("Free & open source", x: 52, y: 710, accent: blue)
    text("Native macOS  ·  No account  ·  No app telemetry", 748, 717, 14,
         color: muted, width: 480)
}

try render("02-cache-review.png") {
    background(accent: mint, section: "Storage cleanup")
    text("Less clutter. More breathing room.", 52, 101, 52, weight: .bold, tracking: -1.8)
    text("Recognize app caches, select several, and review what goes to Trash.",
         54, 174, 20, color: muted)
    text("CACHE INVENTORY / DETAIL", 54, 234, 11, color: mint, weight: .semibold, tracking: 1.7)
    // Inventory card and its selection footer, excluding the large surrounding headers.
    shot("inventory-caches", crop: NSRect(x: 0, y: 360, width: 1581, height: 399),
         at: rect(52, 261, 1166, 1166 * 399 / 1581), radius: 16)
    let features: [(String, String, CGFloat)] = [
        ("Recognize", "App icons beside each cache", 54),
        ("Select", "Multiple caches, one review", 454),
        ("Review", "Choose what moves to Trash", 854),
    ]
    for (index, feature) in features.enumerated() {
        text(String(format: "%02d", index + 1), feature.2, 611, 12,
             color: mint, weight: .semibold, width: 35)
        text(feature.0, feature.2 + 35, 605, 23, weight: .semibold, width: 320, tracking: -0.5)
        text(feature.1, feature.2 + 35, 641, 15, color: muted, width: 320)
    }
    text("Real app capture. Selection shown; no files removed.", 54, 716, 12, color: muted)
}

try render("03-app-usage.png") {
    background(accent: violet, section: "App activity")
    text("Find the apps behind the spike.", 52, 101, 54, weight: .bold, tracking: -1.8)
    text("Live CPU rankings and recent history, down to the app.",
         54, 174, 20, color: muted)
    // CPU graph, four metric cards and the first three complete process rows.
    shot("cpu", crop: NSRect(x: 24, y: 84, width: 1520, height: 630),
         at: rect(52, 228, 1166, 483), radius: 18)
    text("Actual readings on Apple M4. CPU values shown as a percentage of the whole Mac.",
         54, 732, 11, color: muted)
}

// Preserve the product's existing icon instead of inventing a launch-specific logo.
let thumb = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 240,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 960, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: thumb)
NSGraphicsContext.current?.imageInterpolation = .high
icon.draw(in: NSRect(x: 0, y: 0, width: 240, height: 240))
NSGraphicsContext.restoreGraphicsState()
try thumb.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("thumbnail-240.png"))
