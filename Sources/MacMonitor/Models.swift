import AppKit
import SwiftUI

enum MonitorTab: String, CaseIterable, Identifiable, Codable {
  case overview = "Overview"
  case cpu = "CPU"
  case memory = "Memory"
  case disk = "Disk"
  case network = "Network"
  case gpu = "GPU"
  case battery = "Battery"
  case sound = "Sound"
  case bluetooth = "Bluetooth"
  case projects = "Projects"
  var id: String { rawValue }
  var symbol: String {
    switch self {
    case .overview: return "square.grid.2x2"
    case .cpu: return "cpu"
    case .memory: return "memorychip"
    case .disk: return "internaldrive"
    case .network: return "globe"
    case .gpu: return "square.3.layers.3d"
    case .battery: return "battery.100percent"
    case .sound: return "speaker.wave.2"
    case .bluetooth: return "antenna.radiowaves.left.and.right"
    case .projects: return "folder"
    }
  }
  var color: Color {
    switch self {
    case .overview, .cpu: return Color(hex: 0x398eeb)
    case .memory: return Color(hex: 0x9787ed)
    case .disk: return Color(hex: 0xdfa000)
    case .network: return Color(hex: 0x13aa81)
    case .gpu: return Color(hex: 0xe25291)
    case .battery: return Color(hex: 0x2eb53e)
    case .sound: return Color(hex: 0xde54b4)
    case .bluetooth: return Color(hex: 0x16b7d6)
    case .projects: return Color(hex: 0xe76529)
    }
  }
}
extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255,
      blue: Double(hex & 255) / 255)
  }
  static let surface = Color(hex: 0x222224)
  static let window = Color(hex: 0x1b1b1e)
  static let muted = Color(hex: 0x96969e)
}
enum Format {
  static func bytes(_ value: Double, decimals: Int = 2, base: Double = 1000) -> String {
    let v = max(0, value)
    if v >= base * base * base {
      return String(format: "%.*f GB", decimals, v / (base * base * base))
    }
    if v >= base * base { return String(format: "%.0f MB", v / (base * base)) }
    if v >= base { return String(format: "%.0f kB", v / base) }
    return String(format: "%.0f B", v)
  }
  static func memory(_ value: Double, decimals: Int = 2) -> String {
    bytes(value, decimals: decimals, base: 1024)
  }
  static func rate(_ value: Double, bits: Bool = false) -> String {
    if bits {
      let v = value * 8
      return v >= 1_000_000
        ? String(format: "%.1f Mbps", v / 1_000_000) : String(format: "%.0f kbps", v / 1000)
    }
    return bytes(value, decimals: 1) + "/s"
  }
  static func percent(_ value: Double, precise: Bool = false) -> String {
    String(format: precise ? "%.1f%%" : "%.0f%%", value)
  }
  static func watts(_ value: Double?) -> String {
    guard let value else { return "—" }
    return value >= 1 ? String(format: "%.1f W", value) : String(format: "%.0f mW", value * 1000)
  }
  static func duration(_ seconds: Double) -> String {
    let s = Int(max(0, seconds))
    if s >= 86400 { return "\(s/86400)d \((s%86400)/3600)h" }
    if s >= 3600 { return "\(s/3600)h \((s%3600)/60)m" }
    return "\(s/60)m"
  }
}
struct ProcessStat: Identifiable {
  var pid: Int32
  var parent: Int32
  var uid: Int
  var start: UInt64
  var name: String
  var path: String
  var cpu: Double
  var memory: Double
  var read: Double
  var write: Double
  var gpu: Double?
  var power: Double?
  var accessible: Bool
  var id: Int32 { pid }
}
struct AppStat: Identifiable {
  var id: String
  var name: String
  var bundlePath: String?
  var processes: [ProcessStat]
  var icon: NSImage?
  var isSystem = false
  var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
  var memory: Double { processes.reduce(0) { $0 + $1.memory } }
  var read: Double { processes.reduce(0) { $0 + $1.read } }
  var write: Double { processes.reduce(0) { $0 + $1.write } }
  var gpu: Double? {
    let a = processes.compactMap(\.gpu)
    return a.isEmpty ? nil : a.reduce(0, +)
  }
  var power: Double? {
    let a = processes.compactMap(\.power)
    return a.isEmpty ? nil : a.reduce(0, +)
  }
  var download = 0.0
  var upload = 0.0
  func value(for tab: MonitorTab) -> Double {
    switch tab {
    case .cpu: return cpu
    case .memory: return memory
    case .disk: return write
    case .network: return download
    case .gpu: return gpu ?? 0
    case .battery: return power ?? 0
    default: return memory
    }
  }
}
struct BatteryStat {
  var present = false
  var level = 0.0
  var charging = false
  var plugged = false
  var remaining: Double?
  var cycles: Int?
  var health: Double?
  var temperature: Double?
  var watts: Double?
  var status: String {
    !present ? "No battery" : charging ? "Charging" : plugged ? "On AC Power" : "On Battery"
  }
}
struct BluetoothStat: Identifiable {
  var id: String
  var name: String
  var kind: String
  var connected: Bool
  var levels: [(String, Int)]
  var symbol: String {
    kind.contains("Keyboard")
      ? "keyboard"
      : kind.contains("Mouse")
        ? "computermouse"
        : kind.contains("Trackpad") ? "rectangle.and.hand.point.up.left" : "headphones"
  }
}
struct ProjectStat: Identifiable {
  var id: String
  var name: String
  var runtime: String
  var processes: [ProcessStat]
  var ports: [Int]
  var idleSince: Date?
  var memory: Double { processes.reduce(0) { $0 + $1.memory } }
  var cpu: Double { processes.reduce(0) { $0 + $1.cpu } }
}
struct AudioApp: Identifiable {
  var id: String
  var name: String
  var icon: NSImage?
  var objects: [UInt32]
  var playing: Bool
}
struct AudioDevice: Identifiable {
  var id: UInt32
  var name: String
}
struct Sample: Codable, Identifiable {
  var timestamp: Double
  var cpu: Double
  var memory: Double
  var gpu: Double?
  var diskRead: Double
  var diskWrite: Double
  var download: Double
  var upload: Double
  var battery: Double?
  var id: Double { timestamp }
  func value(_ tab: MonitorTab) -> Double {
    switch tab {
    case .cpu, .overview: return cpu
    case .memory: return memory
    case .disk: return diskRead + diskWrite
    case .network: return download
    case .gpu: return gpu ?? 0
    case .battery: return battery ?? 0
    default: return 0
    }
  }
}
struct Snapshot {
  var date = Date()
  var observedDuration = 0.0
  var cpu = 0.0
  var user = 0.0
  var system = 0.0
  var load = 0.0
  var cores = ProcessInfo.processInfo.processorCount
  var performanceCores = 0
  var efficiencyCores = 0
  var totalMemory = 0.0
  var appMemory = 0.0
  var wired = 0.0
  var compressed = 0.0
  var cached = 0.0
  var free = 0.0
  var swap = 0.0
  var pressure = "Normal"
  var diskTotal = 0.0
  var diskFree = 0.0
  var diskRead = 0.0
  var diskWrite = 0.0
  var download = 0.0
  var upload = 0.0
  var interface = "en0"
  var interfaceType = "Network"
  var volumes: [String] = []
  var gpu: Double?
  var gpuMemory: Double?
  var gpuName = "GPU"
  var battery = BatteryStat()
  var cpuTemperature: Double?
  var gpuTemperature: Double?
  var fans: [Double] = []
  var apps: [AppStat] = []
  var projects: [ProjectStat] = []
  var processCount = 0
  var networkAvailable = false
  var uptime = ProcessInfo.processInfo.systemUptime
  // Apple Silicon reserves RAM outside the VM page buckets. Include it in
  // usage rather than treating that memory as available to applications.
  var reservedMemory: Double {
    max(0, totalMemory - appMemory - wired - compressed - cached - free)
  }
  var memoryUsed: Double { max(0, totalMemory - cached - free) }
  var availableMemory: Double { max(0, totalMemory - memoryUsed) }
  var sample: Sample {
    Sample(
      timestamp: date.timeIntervalSince1970, cpu: cpu, memory: memoryUsed, gpu: gpu,
      diskRead: diskRead, diskWrite: diskWrite, download: download, upload: upload,
      battery: battery.present ? battery.level : nil)
  }
}
enum HistoryRange: String, CaseIterable {
  case live = "Live"
  case hour = "1 h"
  case twelve = "12 h"
  case day = "24 h"
  case week = "7 d"
  case month = "30 d"
  var seconds: Double {
    switch self {
    case .live: return 120
    case .hour: return 3600
    case .twelve: return 43200
    case .day: return 86400
    case .week: return 604800
    case .month: return 2_592_000
    }
  }
}
