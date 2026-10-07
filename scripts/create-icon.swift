import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(
  "AppIcon.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
  let image = NSImage(size: NSSize(width: size, height: size))
  image.lockFocus()
  let dimension = CGFloat(size)
  let rect = NSRect(
    x: dimension * 0.08, y: dimension * 0.08, width: dimension * 0.84, height: dimension * 0.84)
  let background = NSBezierPath(
    roundedRect: rect, xRadius: dimension * 0.2, yRadius: dimension * 0.2)
  NSGradient(
    starting: NSColor(red: 0.15, green: 0.17, blue: 0.22, alpha: 1),
    ending: NSColor(red: 0.055, green: 0.06, blue: 0.09, alpha: 1))!.draw(in: background, angle: 90)
  let line = NSBezierPath()
  line.lineWidth = dimension * 0.055
  line.lineJoinStyle = .round
  line.lineCapStyle = .round
  let points: [(CGFloat, CGFloat)] = [
    (0.23, 0.49), (0.34, 0.49), (0.40, 0.66), (0.49, 0.29), (0.59, 0.73), (0.65, 0.49),
    (0.77, 0.49),
  ]
  for (i, p) in points.enumerated() {
    let point = NSPoint(x: p.0 * dimension, y: p.1 * dimension)
    if i == 0 { line.move(to: point) } else { line.line(to: point) }
  }
  NSColor(red: 0.25, green: 0.59, blue: 1, alpha: 1).setStroke()
  line.stroke()
  image.unlockFocus()
  let data = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(
    using: .png, properties: [:])!
  let names: [String]
  switch size {
  case 16: names = ["icon_16x16.png"]
  case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
  case 64: names = ["icon_32x32@2x.png"]
  case 128: names = ["icon_128x128.png"]
  case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
  case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
  default: names = ["icon_512x512@2x.png"]
  }
  for name in names { try data.write(to: folder.appendingPathComponent(name)) }
}
