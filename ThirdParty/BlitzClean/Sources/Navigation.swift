import AppKit
import SwiftUI

enum CleanPage: String, CaseIterable, Identifiable {
  case overview = "Overview"
  case memory = "Memory"
  case cpu = "CPU"
  case storage = "Storage"
  case recovery = "Revive apps"
  case projects = "Projects"
  case settings = "Settings"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .overview: "square.grid.2x2"
    case .memory: "memorychip"
    case .cpu: "cpu"
    case .storage: "internaldrive"
    case .recovery: "waveform.path.ecg"
    case .projects: "folder"
    case .settings: "gearshape"
    }
  }

  static let main: [Self] = [.overview, .memory, .cpu, .storage, .recovery, .projects]

  static func destination(for window: String) -> Self? {
    switch window {
    case "workspace": .projects
    case "storage-breakdown": .storage
    case "memory-rescue", "processes": .memory
    case "app-recovery": .recovery
    default: nil
    }
  }

  /// Pages removed in 1.0.12 open where their feature lives now.
  static func restored(_ value: String?) -> Self {
    switch value {
    case "AI workers", "Processes", "History": .memory
    case "Worktrees", "Developer storage": .storage
    case "Project folders": .settings
    default: value.flatMap(Self.init(rawValue:)) ?? .overview
    }
  }
}

enum CleanStoragePage: String, CaseIterable {
  case browse = "Browse"
  case mac = "Inventory"
  case cleanup = "Cleanup"

  static func restored(_ value: String?) -> Self {
    switch value {
    case "Mac": .mac
    case "Caches", "Dependencies": .cleanup
    case "Files & media", "Files": .browse
    default: value.flatMap(Self.init(rawValue:)) ?? .browse
    }
  }
}

@MainActor
extension OpenWindowAction {
  @MainActor func dashboard() {
    callAsFunction(id: "dashboard")
    NSApp.activate(ignoringOtherApps: true)
  }
}

final class CleanNavigation: ObservableObject {
  private let defaults: UserDefaults
  @Published var page: CleanPage {
    didSet { defaults.set(page.rawValue, forKey: "navigation.page") }
  }
  @Published var storagePage: CleanStoragePage {
    didSet { defaults.set(storagePage.rawValue, forKey: "navigation.storagePage") }
  }

  init(_ defaults: UserDefaults = .standard) {
    self.defaults = defaults
    let savedPage = defaults.string(forKey: "navigation.page")
    page = CleanPage.restored(savedPage)
    storagePage =
      savedPage == "Developer storage" || savedPage == "Worktrees"
      ? .cleanup : CleanStoragePage.restored(defaults.string(forKey: "navigation.storagePage"))
    defaults.set(page.rawValue, forKey: "navigation.page")
    defaults.set(storagePage.rawValue, forKey: "navigation.storagePage")
  }

  /// Opens the page that resolves the limiting resource.
  func review(_ pressure: PressureAssessment) {
    if pressure.limit == .disk {
      storagePage = .cleanup
      page = .storage
    } else {
      page = .projects
    }
  }
}


struct AppMemoryIcon: View {
  let app: MemoryApp
  var body: some View {
    ApplicationIcon(source: .file(app.bundleURL.path), size: 28, fallback: "app")
  }
}
