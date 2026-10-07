import Foundation
import ImageIO
import SwiftUI

enum DashboardImage {
  @MainActor static func render<Content: View>(_ renderer: ImageRenderer<Content>) -> CGImage? {
    var image: CGImage?
    renderer.render(rasterizationScale: renderer.scale) { size, draw in
      let scale = renderer.scale
      guard let context = CGContext(
        data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return }
      context.scaleBy(x: scale, y: scale)
      draw(context)
      image = context.makeImage()
    }
    return image
  }

  static func png(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
      data as CFMutableData, "public.png" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return data as Data
  }
}
