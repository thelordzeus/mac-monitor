import Foundation

enum AppIdentity {
  static let name = "Mac Pulse"
  static let exportName = "Mac-Pulse"
  static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
      ?? "Development"
  }
}
