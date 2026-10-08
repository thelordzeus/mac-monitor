import Foundation

public struct ResourceApp: Sendable {
  public let id: String, name: String, identity: String
  public let cpu: Double, memory: Double, write: Double, network: Double
  public init(
    id: String, name: String, identity: String, cpu: Double, memory: Double, write: Double,
    network: Double
  ) {
    self.id = id
    self.name = name
    self.identity = identity
    self.cpu = cpu
    self.memory = memory
    self.write = write
    self.network = network
  }
}
public struct ResourceObservation: Sendable {
  public let date: Date, duration: Double, cpu: Double, diskFree: Double?, pressure: Int?,
    swap: Double?, temperature: Double?
  public let apps: [ResourceApp]
  public init(
    date: Date, duration: Double, cpu: Double, diskFree: Double?, pressure: Int?, swap: Double?,
    temperature: Double?, apps: [ResourceApp]
  ) {
    self.date = date
    self.duration = duration
    self.cpu = cpu
    self.diskFree = diskFree
    self.pressure = pressure
    self.swap = swap
    self.temperature = temperature
    self.apps = apps
  }
}
public enum AlertMetric: String, Codable, CaseIterable, Identifiable, Sendable {
  case cpu = "CPU usage"
  case memoryGrowth = "App memory growth"
  case diskWrite = "App disk writes"
  case network = "App network traffic"
  case diskFree = "Low disk space"
  case pressure = "Memory pressure"
  case temperature = "CPU temperature"
  public var id: String { rawValue }
  public var unit: String {
    switch self {
    case .cpu: "% of this Mac"
    case .memoryGrowth: "MiB in 10 minutes"
    case .diskWrite, .network: "MB/s"
    case .diskFree: "GB available"
    case .pressure: "1 = warning, 2 = critical"
    case .temperature: "°C"
    }
  }
  public var isAppMetric: Bool { [.cpu, .memoryGrowth, .diskWrite, .network].contains(self) }
  public var defaultThreshold: Double {
    switch self {
    case .cpu: 70
    case .memoryGrowth: 1024
    case .diskWrite: 100
    case .network: 50
    case .diskFree: 10
    case .pressure: 1
    case .temperature: 85
    }
  }
}
public struct AlertRule: Identifiable, Codable, Equatable, Sendable {
  public var id: UUID, metric: AlertMetric, threshold: Double, seconds: Double, enabled: Bool,
    appID: String?
  public init(
    id: UUID = UUID(), metric: AlertMetric, threshold: Double? = nil, seconds: Double = 60,
    enabled: Bool = true, appID: String? = nil
  ) {
    self.id = id
    self.metric = metric
    self.threshold = threshold ?? metric.defaultThreshold
    self.seconds = seconds
    self.enabled = enabled
    self.appID = appID
  }
  public static var defaults: [Self] {
    AlertMetric.allCases.map { Self(metric: $0, seconds: $0 == .memoryGrowth ? 0 : 60) }
  }
}
public struct QuietHours: Codable, Equatable, Sendable {
  public var enabled: Bool, startHour: Int, endHour: Int
  public init(enabled: Bool = false, startHour: Int = 22, endHour: Int = 8) {
    self.enabled = enabled
    self.startHour = startHour
    self.endHour = endHour
  }
  public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
    guard enabled else { return false }
    let hour = calendar.component(.hour, from: date)
    return startHour == endHour
      || (startHour < endHour
        ? hour >= startHour && hour < endHour : hour >= startHour || hour < endHour)
  }
}
public struct ResourceFinding: Identifiable, Sendable {
  public let id: String, title: String, detail: String, metric: AlertMetric, appID: String?
}
/// Accumulates observed time, never treating sleep/pause gaps or restarted apps as sustained load.
public struct ObservationEngine {
  private var elapsed: [String: Double] = [:]
  private var lastAlerts: [String: Date] = [:]
  private var baseline: [String: (Date, Double)] = [:]
  private var identities: [String: String] = [:]
  private var recentGrowth: [String: (Date, Double)] = [:]
  private var lastDate: Date?
  public private(set) var findings: [ResourceFinding] = []
  public init() {}
  public mutating func reset() {
    elapsed = [:]
    baseline = [:]
    identities = [:]
    lastDate = nil
    findings = []
    recentGrowth = [:]
  }
  public mutating func observe(_ s: ResourceObservation, rules: [AlertRule]) -> [ResourceFinding] {
    let gap =
      lastDate.map { s.date.timeIntervalSince($0) > max(30, s.duration * 3) || s.date <= $0 }
      ?? false
    if gap || s.duration <= 0 { reset() }
    lastDate = s.date
    guard s.duration > 0 else { return [] }
    let activeIDs = Set(s.apps.map(\.id))
    baseline = baseline.filter { activeIDs.contains($0.key) }
    for app in s.apps {
      if identities[app.id] != app.identity {
        baseline[app.id] = (s.date, app.memory)
        recentGrowth[app.id] = nil
        elapsed = elapsed.filter { !$0.key.hasSuffix(":" + app.id) }
      }
      if let base = baseline[app.id], s.date.timeIntervalSince(base.0) >= 600 {
        recentGrowth[app.id] = (s.date, max(0, app.memory - base.1) / 1_048_576)
        baseline[app.id] = (s.date, app.memory)
      }
      identities[app.id] = app.identity
    }
    var current: [ResourceFinding] = []
    var alerts: [ResourceFinding] = []
    var validKeys = Set<String>()
    for rule in rules
    where rule.enabled && rule.threshold.isFinite && rule.threshold > 0 && rule.seconds.isFinite
      && rule.seconds >= 0
    {
      let candidates: [(String, String, Double?, String?)]
      if rule.metric.isAppMetric {
        candidates = s.apps.filter { rule.appID == nil || $0.id == rule.appID }.map { app in
          let value: Double?
          switch rule.metric {
          case .cpu: value = app.cpu
          case .memoryGrowth:
            if let growth = recentGrowth[app.id], s.date.timeIntervalSince(growth.0) <= 60 {
              value = growth.1
            } else {
              value = nil
            }
          case .diskWrite: value = app.write / 1_000_000
          case .network: value = app.network / 1_000_000
          default: value = nil
          }
          return (app.id, app.name, value, app.id)
        }
      } else {
        let value: Double?
        switch rule.metric {
        case .diskFree: value = s.diskFree.map { $0 / 1_000_000_000 }
        case .pressure: value = s.pressure.map(Double.init)
        case .temperature: value = s.temperature
        default: value = nil
        }
        candidates = [("system", "Your Mac", value, nil)]
      }
      for (id, name, value, appID) in candidates {
        let key = rule.id.uuidString + ":" + id
        validKeys.insert(key)
        let identityKey = key + ":" + (identities[id] ?? "system")
        guard let value, value.isFinite,
          rule.metric == .diskFree ? value < rule.threshold : value >= rule.threshold
        else {
          elapsed[key] = nil
          continue
        }
        elapsed[key, default: 0] += min(s.duration, 30)
        guard elapsed[key, default: 0] >= rule.seconds else { continue }
        let reading =
          rule.metric == .pressure
          ? (value >= 2 ? "Critical memory pressure" : "Elevated memory pressure")
          : String(format: "%.1f %@", value, rule.metric.unit)
        let finding = ResourceFinding(
          id: key, title: title(rule.metric, name),
          detail: reading + String(format: " · observed for %.0f seconds", elapsed[key] ?? 0),
          metric: rule.metric, appID: appID)
        current.append(finding)
        if s.date.timeIntervalSince(lastAlerts[identityKey] ?? .distantPast) >= 1800 {
          lastAlerts[identityKey] = s.date
          alerts.append(finding)
        }
      }
    }
    elapsed = elapsed.filter { validKeys.contains($0.key) }
    identities = identities.filter { activeIDs.contains($0.key) }
    recentGrowth = recentGrowth.filter { activeIDs.contains($0.key) }
    findings = current
    return alerts
  }
  private func title(_ metric: AlertMetric, _ name: String) -> String {
    switch metric {
    case .cpu: "\(name) is keeping the CPU busy"
    case .memoryGrowth: "\(name)'s memory grew in ten minutes"
    case .diskWrite: "\(name) is writing heavily"
    case .network: "\(name) is moving a lot of data"
    case .diskFree: "Your startup disk is running low"
    case .pressure: "Memory pressure needs attention"
    case .temperature: "Your CPU temperature is elevated"
    }
  }
}
