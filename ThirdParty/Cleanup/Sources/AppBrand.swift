import AppKit
import SwiftUI

enum AppBrand {
  static let name = "Mac Pulse"
  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }
  static let accent = PulseUI.mint
  static let bundleIdentifier = "local.macmonitor.app"
  @MainActor static let icon = resourceImage("AppIcon.icns")
  /// An image bundled in the app's Resources; absent when running outside the app bundle.
  @MainActor static func resourceImage(_ file: String) -> NSImage? {
    let name = (file as NSString).deletingPathExtension
    let ext = (file as NSString).pathExtension
    return Bundle.main.url(forResource: name, withExtension: ext).flatMap(NSImage.init(contentsOf:))
  }
}

struct BrandMark: View {
  var body: some View {
    Group {
      if let icon = AppBrand.icon {
        Image(nsImage: icon).resizable().scaledToFit()
      } else {
        fallback
      }
    }
    .frame(width: 40, height: 40)
    .accessibilityLabel(AppBrand.name)
  }

  private var fallback: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 10).fill(PulseUI.sidebarBackground)
      Image(systemName: "bolt.fill")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(AppBrand.accent)
    }
  }
}
