// Marketing assets only. Does not build or modify the application.
// Usage: swift scripts/prepare-launch-media.swift <capture-directory> <output-directory>
import AppKit
import AVFoundation
import CoreVideo
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fatalError("Provide capture and output directories") }
let capture = URL(fileURLWithPath: arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
let source = output.appendingPathComponent("source", isDirectory: true)
try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
let width = 1270, height = 760
let blue = NSColor(srgbRed: 0.29, green: 0.57, blue: 1, alpha: 1)
let green = NSColor(srgbRed: 0.20, green: 0.78, blue: 0.65, alpha: 1)
let orange = NSColor(srgbRed: 0.95, green: 0.43, blue: 0.20, alpha: 1)
let muted = NSColor(srgbRed: 0.64, green: 0.68, blue: 0.75, alpha: 1)
let icon = NSImage(contentsOfFile: "Resources/AppIcon.iconset/icon_512x512@2x.png")!
func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
  NSRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}
func text(_ value: String, x: CGFloat, y: CGFloat, w: CGFloat, size: CGFloat,
          color: NSColor = .white, weight: NSFont.Weight = .regular) {
  let paragraph = NSMutableParagraphStyle()
  paragraph.lineBreakMode = .byWordWrapping
  (value as NSString).draw(in: box(x, y, w, size * 2.8), withAttributes: [
    .font: NSFont.systemFont(ofSize: size, weight: weight),
    .foregroundColor: color, .paragraphStyle: paragraph,
  ])
}
func bitmap(_ draw: () -> Void) -> NSBitmapImageRep {
  let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: image)
  NSGraphicsContext.current?.imageInterpolation = .high
  draw()
  NSGraphicsContext.restoreGraphicsState()
  return image
}
func save(_ image: NSBitmapImageRep, _ filename: String) throws {
  try image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(filename))
}
func base(accent: NSColor, number: String) {
  NSGradient(starting: NSColor(srgbRed: 0.065, green: 0.075, blue: 0.10, alpha: 1),
    ending: NSColor(srgbRed: 0.10, green: 0.12, blue: 0.16, alpha: 1))!
    .draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: -25)
  icon.draw(in: box(42, 28, 33, 33))
  text("MAC PULSE", x: 87, y: 34, w: 250, size: 16, weight: .semibold)
  text(number, x: 1164, y: 35, w: 70, size: 14, color: muted)
  accent.withAlphaComponent(0.9).setFill()
  NSBezierPath(roundedRect: box(42, 81, 42, 4), xRadius: 2, yRadius: 2).fill()
}
var shots: [String: NSImage] = [:]
for name in ["overview", "cpu", "cleanup", "inventory-caches", "projects"] {
  let bytes = try Data(contentsOf: capture.appendingPathComponent(name + ".png"))
  guard let rep = NSBitmapImageRep(data: bytes), let cg = rep.cgImage else { fatalError("Invalid capture: \(name)") }
  let normalized = NSBitmapImageRep(cgImage: cg)
  try normalized.representation(using: .png, properties: [:])!.write(to: source.appendingPathComponent(name + ".png"))
  shots[name] = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
}
func screenshot(_ name: String, area: NSRect, cropTopFraction: CGFloat = 1) {
  let image = shots[name]!
  let visibleHeight = image.size.height * cropTopFraction
  let scale = min(area.width / image.size.width, area.height / visibleHeight)
  let frame = NSRect(x: area.midX - image.size.width * scale / 2,
    y: area.midY - visibleHeight * scale / 2,
    width: image.size.width * scale, height: visibleHeight * scale)
  let clip = NSBezierPath(roundedRect: frame, xRadius: 15, yRadius: 15)
  NSGraphicsContext.saveGraphicsState()
  let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
  shadow.shadowBlurRadius = 16; shadow.shadowOffset = NSSize(width: 0, height: -8); shadow.set()
  NSColor.black.setFill(); clip.fill()
  NSGraphicsContext.restoreGraphicsState()
  NSGraphicsContext.saveGraphicsState(); clip.addClip()
  image.draw(in: frame, from: NSRect(x: 0, y: image.size.height - visibleHeight,
    width: image.size.width, height: visibleHeight), operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
  NSColor.white.withAlphaComponent(0.10).setStroke(); clip.lineWidth = 1; clip.stroke()
}
struct Scene {
  let file: String, shot: String, title: String, subtitle: String, footnote: String
  let accent: NSColor
  let crop: CGFloat
}
let scenes = [
  Scene(file: "01-monitoring.png", shot: "overview", title: "See what your Mac is doing.",
    subtitle: "CPU, memory, GPU, disk and network in one native dashboard.",
    footnote: "Actual Apple M4 readings · Overview detail · Available sensors vary by Mac", accent: blue, crop: 0.75),
  Scene(file: "02-cache-review.png", shot: "inventory-caches", title: "Know what you are selecting.",
    subtitle: "Recognize app caches. Select several. Review before removal.",
    footnote: "Selection shown only · No files removed · Selected size is not reclaimed space", accent: green, crop: 1),
  Scene(file: "03-projects.png", shot: "projects", title: "Keep an eye on development servers.",
    subtitle: "See runtimes, listening ports, memory and observed CPU inactivity.",
    footnote: "Real local PostgreSQL process · Idle reflects observed CPU, not request activity", accent: orange, crop: 0.36),
  Scene(file: "04-app-usage.png", shot: "cpu", title: "Find the apps behind the numbers.",
    subtitle: "Live app rankings and recent resource history, a click away.",
    footnote: "Actual readings during capture · CPU values are percentages of the whole Mac", accent: blue, crop: 1),
]
var frames: [NSBitmapImageRep] = []
for (index, scene) in scenes.enumerated() {
  let frame = bitmap {
    base(accent: scene.accent, number: String(format: "%02d / 04", index + 1))
    text(scene.title, x: 42, y: 101, w: 1190, size: 37, weight: .bold)
    text(scene.subtitle, x: 42, y: 153, w: 1190, size: 19, color: muted)
    if scene.shot == "projects" {
      screenshot(scene.shot, area: box(42, 220, 1186, 315), cropTopFraction: scene.crop)
      text("Inspect first. Choose what to stop.", x: 64, y: 577, w: 1140, size: 28, weight: .semibold)
      text("Project termination asks for confirmation. Nothing was stopped for this demo.",
        x: 64, y: 621, w: 1140, size: 18, color: muted)
    } else {
      screenshot(scene.shot, area: box(42, 201, 1186, 503), cropTopFraction: scene.crop)
    }
    text(scene.footnote, x: 42, y: 724, w: 1190, size: 12, color: muted)
  }
  try save(frame, scene.file); frames.append(frame)
}
let closing = bitmap {
  base(accent: green, number: "MACOS")
  icon.draw(in: box(42, 147, 104, 104))
  text("Your Mac, in view.", x: 42, y: 284, w: 1180, size: 61, weight: .bold)
  text("System monitoring and storage cleanup. Free. No account.", x: 46, y: 380, w: 1178, size: 26, color: muted)
  text("github.com/thelordzeus/mac-monitor", x: 46, y: 488, w: 1178, size: 32, color: green, weight: .semibold)
  text("Apple Silicon · macOS 14.2+", x: 46, y: 568, w: 1178, size: 21)
  text("Ad hoc signed; not Apple-notarized. First-launch instructions are in the README.",
    x: 46, y: 611, w: 1178, size: 18, color: muted)
  text("Demo assembled from real application captures. No files deleted or servers stopped.",
    x: 46, y: 707, w: 1178, size: 14, color: muted)
}
try save(closing, "05-download.png")
// Keep the app icon unchanged, fitting it to Product Hunt's recommended square size.
let thumb = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 240,
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 960, bitsPerPixel: 32)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: thumb)
NSGraphicsContext.current?.imageInterpolation = .high
icon.draw(in: NSRect(x: 0, y: 0, width: 240, height: 240))
NSGraphicsContext.restoreGraphicsState()
try save(thumb, "thumbnail-240.png")

// A captioned walkthrough of real captures; not a fabricated live screen recording.
let video = output.appendingPathComponent("mac-pulse-demo-40s.mp4")
if FileManager.default.fileExists(atPath: video.path) { try FileManager.default.removeItem(at: video) }
let writer = try AVAssetWriter(outputURL: video, fileType: .mp4)
let vw = 1280, vh = 720, fps: Int32 = 20
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
  AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: vw, AVVideoHeightKey: vh,
  AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_000_000,
    AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
  sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: vw, kCVPixelBufferHeightKey as String: vh,
    kCVPixelBufferCGImageCompatibilityKey as String: true,
    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input); writer.shouldOptimizeForNetworkUse = true
guard writer.startWriting() else { throw writer.error! }
writer.startSession(atSourceTime: .zero)
let ordered = [frames[0], frames[3], frames[1], frames[2], closing]
let durations = [7, 7, 10, 8, 8]
let cgImages = ordered.map { $0.cgImage! }
var frameIndex: Int64 = 0
for (index, seconds) in durations.enumerated() {
  for localFrame in 0..<(seconds * Int(fps)) {
    while !input.isReadyForMoreMediaData {
      if writer.status == .failed { throw writer.error! }
      Thread.sleep(forTimeInterval: 0.005)
    }
    var buffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer) == kCVReturnSuccess,
      let buffer else { fatalError("Could not allocate video frame") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: vw, height: vh,
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.setFillColor(CGColor(gray: 0.065, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: vw, height: vh))
    let scale = min(CGFloat(vw) / CGFloat(width), CGFloat(vh) / CGFloat(height))
    let area = CGRect(x: (CGFloat(vw) - CGFloat(width) * scale) / 2, y: 0,
      width: CGFloat(width) * scale, height: CGFloat(vh))
    context.interpolationQuality = .high
    context.draw(cgImages[index], in: area)
    if index > 0 && localFrame < 8 {
      context.setAlpha(1 - CGFloat(localFrame) / 8)
      context.draw(cgImages[index - 1], in: area)
      context.setAlpha(1)
    }
    context.setFillColor(CGColor(red: 0.20, green: 0.78, blue: 0.65, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: CGFloat(vw) * CGFloat(frameIndex) / 800, height: 3))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: frameIndex, timescale: fps)) else { throw writer.error! }
    frameIndex += 1
  }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { throw writer.error! }
let asset = AVURLAsset(url: video)
let imageGenerator = AVAssetImageGenerator(asset: asset)
imageGenerator.appliesPreferredTrackTransform = true
for second in [3, 10, 20, 28, 36] {
  let image = try imageGenerator.copyCGImage(at: CMTime(value: Int64(second), timescale: 1), actualTime: nil)
  let frame = NSBitmapImageRep(cgImage: image)
  try frame.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("video-check-\(second)s.png"))
}
print("Created 5 gallery images, 240px thumbnail, 40-second H.264 MP4 and video verification frames.")
