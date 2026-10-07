import AppKit
import Foundation

struct InventoryCacheOwner: Equatable, Sendable {
  let name: String
  let applicationPath: String?
  let bundleIdentifier: String?
  let processNames: Set<String>
  var fallbackSymbol: String { applicationPath == nil ? "shippingbox" : "app" }
}

struct InventoryCacheApplication: Equatable, Sendable {
  let name: String
  let path: String
  let bundleIdentifier: String
  let executable: String

  static func read(_ path: String) -> Self? {
    guard let bundle = Bundle(path: path), let identifier = bundle.bundleIdentifier else {
      return nil
    }
    return .init(
      name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
      path: path, bundleIdentifier: identifier,
      executable: bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? "")
  }
}

/// Uses installed apps as well as running apps; a closed app still has its icon.
struct InventoryCacheOwnerCatalog {
  let applications: [InventoryCacheApplication]

  func owner(for path: String) -> InventoryCacheOwner {
    let leaf = URL(fileURLWithPath: path).lastPathComponent
    let lower = leaf.lowercased()
    let aliases: [String: (identifier: String, name: String, processes: Set<String>)] = [
      "codex-runtimes": ("com.openai.codex", "Codex", ["codex"]),
      "codex": ("com.openai.codex", "Codex", ["codex"]),
      "spotify": ("com.spotify.client", "Spotify", ["Spotify"]),
      "arc": ("company.thebrowser.Browser", "Arc", ["Arc"]),
    ]
    let alias = aliases[lower]
    let identifier = alias?.identifier ?? leaf
    let app = applications.first {
      identifier.caseInsensitiveCompare($0.bundleIdentifier) == .orderedSame
    } ?? applications.sorted { $0.bundleIdentifier.count > $1.bundleIdentifier.count }.first {
      identifier.lowercased().hasPrefix($0.bundleIdentifier.lowercased() + ".")
    } ?? applications.first {
      leaf.caseInsensitiveCompare($0.name) == .orderedSame
        || leaf.caseInsensitiveCompare(
          URL(fileURLWithPath: $0.path).deletingPathExtension().lastPathComponent
        ) == .orderedSame
    }
    if let app {
      return .init(
        name: app.name, applicationPath: app.path, bundleIdentifier: app.bundleIdentifier,
        processNames: Set([app.executable].filter { !$0.isEmpty }).union(alias?.processes ?? []))
    }
    if let alias {
      return .init(name: alias.name, applicationPath: nil,
        bundleIdentifier: alias.identifier, processNames: alias.processes)
    }
    let tools: [String: (name: String, processes: Set<String>)] = [
      "homebrew": ("Homebrew", ["brew", "ruby"]),
      "pip": ("pip", ["pip", "pip3"]),
      "uv": ("uv", ["uv"]),
      "yarn": ("Yarn", ["yarn"]),
      "huggingface": ("Hugging Face", ["python", "python3"]),
    ]
    let tool = path.hasSuffix("/.npm/_cacache") ? (name: "npm", processes: Set(["npm", "npx", "pnpm"]))
      : path.hasSuffix("/Library/pnpm/store") ? (name: "pnpm", processes: Set(["pnpm", "node"]))
      : tools[lower]
    return .init(
      name: tool?.name ?? leaf, applicationPath: nil,
      bundleIdentifier: leaf.split(separator: ".").count >= 3 ? leaf : nil,
      processNames: tool?.processes ?? [leaf])
  }

  @MainActor static func installed(_ items: [StorageItem]) -> Self {
    let paths = Set(items.map(\.path)).union(
      NSWorkspace.shared.runningApplications.compactMap { $0.bundleURL?.path })
    return .init(applications: paths.sorted().compactMap(InventoryCacheApplication.read))
  }
}
