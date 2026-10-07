import AppKit
import SwiftUI

enum MenuBarPreferenceKey {
  static let showHealth = "menuBar.showHealth"
  static let showCPU = "menuBar.showCPU"
  static let showMemory = "menuBar.showMemory"
  static let showDisk = "menuBar.showDisk"
  static let memoryDisplay = "menuBar.memoryDisplay"
}

enum MenuBarMemoryDisplay: String, CaseIterable {
  case available = "available"
  case used = "used"
  case percentage = "percentage"

  var label: String {
    switch self {
    case .available: "Available GB"
    case .used: "Used GB"
    case .percentage: "Used %"
    }
  }

  var title: String {
    switch self {
    case .available: "RAM available"
    case .used, .percentage: "RAM used"
    }
  }

  func value(_ snapshot: SystemSnapshot) -> String {
    guard snapshot.ramTotal > 0 else { return "—" }
    switch self {
    case .available: return ByteText.compact(min(snapshot.ramAvailable, snapshot.ramTotal))
    case .used: return ByteText.compact(snapshot.ramUsed)
    case .percentage: return PercentText.make(snapshot.ramUsedRatio)
    }
  }

  func menuValue(_ snapshot: SystemSnapshot) -> String {
    guard snapshot.ramTotal > 0 else { return "—" }
    let suffix = self == .available ? " free" : self == .used ? " used" : ""
    return value(snapshot) + suffix
  }
}

struct MenuBarStatusTextInput {
  let snapshot: SystemSnapshot
  let showDisk: Bool
  let showCPU: Bool
  let showMemory: Bool
  let memoryDisplay: MenuBarMemoryDisplay
}

enum MenuBarStatusText {
  static func make(_ input: MenuBarStatusTextInput) -> String {
    var segments: [String] = []

    if input.showDisk {
      segments.append("\(ByteText.compact(input.snapshot.diskAvailable)) disk free")
    }

    if input.showCPU {
      segments.append("CPU \(percentage(input.snapshot.cpuUsage))")
    }

    if input.showMemory {
      segments.append("RAM \(input.memoryDisplay.menuValue(input.snapshot))")
    }

    return segments.joined(separator: "  ")
  }

  static func percentage(_ ratio: Double?) -> String {
    guard let ratio else {
      return "--"
    }

    return "\((ratio * 100).formatted(.number.precision(.fractionLength(0))))%"
  }
}

enum MenuBarTones {
  static func cpu(_ usage: Double) -> MetricTone {
    if usage >= 0.95 {
      return .critical
    }

    if usage >= 0.75 {
      return .warning
    }

    return .good
  }

  static func disk(_ snapshot: SystemSnapshot) -> MetricTone {
    MetricTone.forDisk(
      DiskCapacityInput(available: snapshot.diskAvailable, total: snapshot.diskTotal))
  }
}

private struct MenuBarMetric: View {
  let title: String
  let value: String
  let tone: MetricTone
  let colored: Bool

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: title == "CPU" ? "cpu" : title == "RAM" ? "memorychip" : "internaldrive")
        .font(.system(size: 12, weight: .medium))
      Text(value).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        .foregroundStyle(colored && (tone == .warning || tone == .critical) ? tone.color : .primary)
    }.fixedSize()
  }
}

@MainActor
enum MenuBarLabelRenderer {
  static func image(content: some View, colored: Bool) -> NSImage {
    let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let renderer = ImageRenderer(
      content:
        content
        .foregroundStyle(colored ? (isDark ? Color.white : Color.black) : Color.black)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .padding(.horizontal, 1)
    )
    renderer.scale = 2

    guard let cgImage = renderer.cgImage else {
      return NSImage()
    }

    let image = NSImage(
      cgImage: cgImage,
      size: NSSize(width: CGFloat(cgImage.width) / 2, height: CGFloat(cgImage.height) / 2))
    image.isTemplate = !colored
    return image
  }
}

struct MenuBarDisplayControls: View {
  @AppStorage(MenuBarPreferenceKey.showHealth) private var showHealth = true
  @AppStorage(MenuBarPreferenceKey.showCPU) private var showCPU = true
  @AppStorage(MenuBarPreferenceKey.showMemory) private var showMemory = true
  @AppStorage(MenuBarPreferenceKey.showDisk) private var showDisk = true
  @AppStorage(MenuBarPreferenceKey.memoryDisplay) private var memoryDisplay = MenuBarMemoryDisplay
    .available

  var body: some View {
    let shown = [showCPU, showMemory, showDisk].filter { $0 }.count
    Group {
      Toggle("CPU", isOn: $showCPU).disabled(showCPU && shown == 1)
      Toggle("Memory", isOn: $showMemory).disabled(showMemory && shown == 1)
      if showMemory {
        BlitzSegmentedPicker(
          title: "Memory value", options: MenuBarMemoryDisplay.allCases,
          selection: $memoryDisplay, label: { $0.label }
        )
        .frame(maxWidth: 360)
        .help("Available memory includes memory macOS can reclaim for apps.")
      }
      Toggle("Disk free", isOn: $showDisk).disabled(showDisk && shown == 1)
      Toggle("Status colors", isOn: $showHealth).disabled(shown == 0)
    }.toggleStyle(BlitzSwitchStyle())
      .help(shown == 1 ? "Keep at least one value in the menu bar." : "")
  }
}
