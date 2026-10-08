import AppKit
import CleanupCore
import Combine
import SwiftUI
import SystemBridge
import UserNotifications
import PulseCore

struct MonitorAlert: Identifiable {
  let id = UUID()
  var title: String
  var detail: String
  var date = Date()
}
final class MonitorStore: ObservableObject {
  @MainActor lazy var storageTracking = StorageGrowthModel()
  @MainActor lazy var connectivity = ConnectivityModel()
  @Published var alertSettingsRequested = false
  @Published var menuPanelTab: MonitorTab?
  @Published var insights: [ResourceFinding] = []
  @Published var alertRules: [AlertRule] = {
    UserDefaults.standard.data(forKey: "alertRules").flatMap { try? JSONDecoder().decode([AlertRule].self, from: $0) } ?? AlertRule.defaults
  }() { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(alertRules), forKey: "alertRules"); ruleEngine.reset() } }
  @Published var quietHours: QuietHours = {
    UserDefaults.standard.data(forKey: "quietHours").flatMap { try? JSONDecoder().decode(QuietHours.self, from: $0) } ?? QuietHours()
  }() { didSet { UserDefaults.standard.set(try? JSONEncoder().encode(quietHours), forKey: "quietHours") } }
  @Published var independentMenuItems = UserDefaults.standard.bool(forKey: "independentMenuItems") {
    didSet { UserDefaults.standard.set(independentMenuItems, forKey: "independentMenuItems") }
  }
  @Published var floatingDashboard = UserDefaults.standard.bool(forKey: "floatingDashboard") {
    didSet { UserDefaults.standard.set(floatingDashboard, forKey: "floatingDashboard") }
  }
  private var ruleEngine = ObservationEngine()
  private var insightEngine = ObservationEngine()
  private let insightRules = AlertRule.defaults
  @Published var snapshot = Snapshot()
  @Published var selectedTab = MonitorTab.overview
  @Published var samples: [Sample] = []
  @Published var liveSamples: [Sample] = []
  @Published var historyRange = HistoryRange.live { didSet { reloadHistory() } }
  @Published var search = ""
  @Published var showSystem = UserDefaults.standard.bool(forKey: "showSystem") {
    didSet { UserDefaults.standard.set(showSystem, forKey: "showSystem") }
  }
  @Published var paused = false {
    didSet {
      if oldValue != paused { ruleEngine.reset(); insightEngine.reset(); insights = []; queue.async { self.collector.resetBaselines() } }
    }
  }
  @Published var selectedApp: AppStat?
  @Published var appHistory: [Sample] = []
  @Published var settingsVisible = false
  @Published var alertsVisible = false
  @Published var alerts: [MonitorAlert] = []
  @Published var message: String?
  @Published var today = Totals()
  @Published var week = Totals()
  @Published var month = Totals()
  @Published var interval: Double = UserDefaults.standard.object(forKey: "interval") as? Double ?? 2
  {
    didSet {
      UserDefaults.standard.set(interval, forKey: "interval")
      restartTimer()
    }
  }
  @Published var networkBits = UserDefaults.standard.bool(forKey: "networkBits") {
    didSet { UserDefaults.standard.set(networkBits, forKey: "networkBits") }
  }
  @Published var perCoreCPU = UserDefaults.standard.bool(forKey: "perCoreCPU") {
    didSet { UserDefaults.standard.set(perCoreCPU, forKey: "perCoreCPU") }
  }
  @Published var fahrenheit = UserDefaults.standard.bool(forKey: "fahrenheit") {
    didSet { UserDefaults.standard.set(fahrenheit, forKey: "fahrenheit") }
  }
  @Published var notifications = UserDefaults.standard.bool(forKey: "notifications") {
    didSet {
      UserDefaults.standard.set(notifications, forKey: "notifications")
      if notifications { requestNotifications() }
    }
  }
  @Published var tabOrder: [MonitorTab] = MonitorTab.allCases
  @Published var hiddenTabs: Set<MonitorTab> = []
  @Published var hiddenCards: Set<MonitorTab> = []
  @Published var pinnedApps: Set<String> = []
  @Published var menuMetrics: Set<MonitorTab> = [.cpu, .memory]
  let audio = AudioController()
  let bluetooth = BluetoothController()
  private var cleanupInstance: CleanupWorkspace?
  @MainActor func cleanupWorkspace() -> CleanupWorkspace {
    if let cleanupInstance { return cleanupInstance }
    let workspace = CleanupWorkspace()
    workspace.update(cleanupMetrics)
    cleanupInstance = workspace
    return workspace
  }
  var cleanupMetrics: CleanupMetrics {
    CleanupMetrics(diskAvailable: snapshot.diskFree, diskTotal: snapshot.diskTotal,
      ramAvailable: snapshot.availableMemory, ramTotal: snapshot.totalMemory,
      cpuPercent: snapshot.cpu, pressure: snapshot.pressure, date: snapshot.date)
  }
  @MainActor func stopCleanup() { cleanupInstance?.shutdown() }
  private let queue = DispatchQueue(label: "MacMonitor.collector", qos: .utility)
  private let collector = Collector()
  private var history: HistoryStore?
  private var timer: Timer?
  private var inFlight = false
  private var lastAlert: [String: Date] = [:]
  private var count = 0
  private var subscriptions = Set<AnyCancellable>()
  var visibleTabs: [MonitorTab] { tabOrder.filter { !hiddenTabs.contains($0) } }
  var chartSamples: [Sample] { historyRange == .live ? liveSamples : samples }
  var apps: [AppStat] {
    snapshot.apps.filter {
      (showSystem || !$0.isSystem)
        && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
    }.sorted {
      let p0 = pinnedApps.contains($0.id)
      let p1 = pinnedApps.contains($1.id)
      if p0 != p1 { return p0 }
      return $0.value(for: selectedTab) > $1.value(for: selectedTab)
    }
  }
  func topApp(for tab: MonitorTab) -> AppStat? {
    snapshot.apps.filter { !$0.isSystem }.max { $0.value(for: tab) < $1.value(for: tab) }
  }
  var displayedAppHistory: [Sample] {
    let tab = selectedTab == .overview ? MonitorTab.memory : selectedTab
    guard tab == .cpu else { return appHistory }
    return appHistory.map { point in
      var point = point
      point.cpu = normalizedCPU(point.cpu)
      return point
    }
  }
  init(start: Bool = true) {
    if let raw = UserDefaults.standard.stringArray(forKey: "tabOrder") {
      tabOrder = raw.compactMap(MonitorTab.init(rawValue:))
    }
    // Preserve the user's order when a release adds a new tab.
    var seen = Set<MonitorTab>()
    tabOrder = tabOrder.filter { seen.insert($0).inserted }
    tabOrder += MonitorTab.allCases.filter { !seen.contains($0) }
    hiddenTabs = Set(
      (UserDefaults.standard.stringArray(forKey: "hiddenTabs") ?? []).compactMap(
        MonitorTab.init(rawValue:)))
    hiddenCards = Set(
      (UserDefaults.standard.stringArray(forKey: "hiddenCards") ?? []).compactMap(
        MonitorTab.init(rawValue:)))
    pinnedApps = Set(UserDefaults.standard.stringArray(forKey: "pinnedApps") ?? [])
    if let raw = UserDefaults.standard.stringArray(forKey: "menuMetrics") {
      menuMetrics = Set(raw.compactMap(MonitorTab.init(rawValue:)))
    }
    audio.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    bluetooth.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
      in: &subscriptions)
    NotificationCenter.default.publisher(for: CleanupWorkspace.openNotification)
      .receive(on: RunLoop.main).sink { [weak self] _ in
        self?.selectedTab = .cleanup
      }.store(in: &subscriptions)
    if start {
      queue.async { self.history = HistoryStore() }
      refresh()
      restartTimer()
    }
  }
  func saveLayout() {
    UserDefaults.standard.set(tabOrder.map(\.rawValue), forKey: "tabOrder")
    UserDefaults.standard.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs")
    UserDefaults.standard.set(hiddenCards.map(\.rawValue), forKey: "hiddenCards")
    UserDefaults.standard.set(pinnedApps.sorted(), forKey: "pinnedApps")
    UserDefaults.standard.set(menuMetrics.map(\.rawValue), forKey: "menuMetrics")
    if hiddenTabs.contains(selectedTab) { selectedTab = .overview }
  }
  func resetLayout() {
    tabOrder = MonitorTab.allCases
    hiddenTabs = []
    hiddenCards = []
    menuMetrics = [.cpu, .memory]
    saveLayout()
  }
  private func restartTimer() {
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: max(1, interval), repeats: true) {
      [weak self] _ in self?.refresh()
    }
  }
  func refresh() {
    guard !paused, !inFlight else { return }
    inFlight = true
    queue.async {
      let s = self.collector.collect(maxInterval: max(10, self.interval * 3))
      self.history?.append(s, duration: s.observedDuration)
      let day = Calendar.current.startOfDay(for: s.date)
      let t = self.history?.totals(since: day) ?? Totals()
      let w = self.history?.totals(since: s.date.addingTimeInterval(-604800)) ?? Totals()
      let m = self.history?.totals(since: s.date.addingTimeInterval(-2_592_000)) ?? Totals()
      DispatchQueue.main.async {
        self.snapshot = s
        self.cleanupInstance?.update(self.cleanupMetrics)
        self.today = t
        self.week = w
        self.month = m
        self.inFlight = false
        if s.observedDuration > 0 { self.liveSamples.append(s.sample) }
        self.liveSamples.removeAll { $0.timestamp < s.date.timeIntervalSince1970 - 120 }
        if let selected = self.selectedApp,
          let updated = s.apps.first(where: { $0.id == selected.id })
        {
          self.selectedApp = updated
        }
        self.audio.refresh(apps: s.apps)
        self.checkAlerts(s)
        self.count += 1
        if self.count % 15 == 0 && self.historyRange != .live { self.reloadHistory() }
      }
    }
  }
  func reloadHistory() {
    let range = historyRange
    guard range != .live else { return }
    queue.async {
      let points = self.history?.samples(since: Date().addingTimeInterval(-range.seconds)) ?? []
      DispatchQueue.main.async { if self.historyRange == range { self.samples = points } }
    }
  }
  func openApp(_ app: AppStat) {
    selectedApp = app
    appHistory = []
    let tab = selectedTab == .overview ? MonitorTab.memory : selectedTab
    queue.async {
      let points =
        self.history?.samples(
          since: Date().addingTimeInterval(-max(3600, self.historyRange.seconds)), appID: app.id,
          tab: tab) ?? []
      DispatchQueue.main.async { if self.selectedApp?.id == app.id { self.appHistory = points } }
    }
  }
  func normalizedCPU(_ value: Double) -> Double {
    perCoreCPU ? value : value / Double(snapshot.cores)
  }
  func value(_ app: AppStat, tab: MonitorTab) -> String {
    switch tab {
    case .cpu: return Format.percent(normalizedCPU(app.cpu), precise: true)
    case .memory: return Format.memory(app.memory)
    case .disk: return Format.rate(app.write)
    case .network:
      return snapshot.networkAvailable ? Format.rate(app.download, bits: networkBits) : "—"
    case .gpu: return app.gpu.map { Format.percent($0, precise: true) } ?? "—"
    case .battery: return Format.watts(app.power)
    default: return Format.memory(app.memory)
    }
  }
  func temperature(_ t: Double?) -> String {
    t.map { String(format: "%.0f°%@", fahrenheit ? $0 * 1.8 + 32 : $0, fahrenheit ? "F" : "C") }
      ?? "—"
  }
  func stop(_ processes: [ProcessStat], force: Bool = false) {
    let failures = processes.compactMap { p -> String? in
      let result = mm_signal(p.pid, p.start, force ? SIGKILL : SIGTERM)
      return result != 0 && result != ESRCH
        ? "\(p.name): \(String(cString: strerror(result)))" : nil
    }
    if !failures.isEmpty { message = failures.joined(separator: "\n") }
    refresh()
  }
  func quitApp(_ app: AppStat, force: Bool) {
    if !force,
      let running = app.processes.compactMap({ NSRunningApplication(processIdentifier: $0.pid) })
        .first(where: { $0.bundleURL?.path == app.bundlePath }), running.terminate()
    {
      return
    }
    stop(app.processes, force: force)
  }
  func flushHistory() {
    queue.sync { history?.flush() }
    audio.reset()
  }
  private func requestNotifications() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
      granted, error in
      DispatchQueue.main.async {
        if !granted {
          self.message =
            error?.localizedDescription
            ?? "Enable notifications for \(AppIdentity.name) in System Settings."
        }
      }
    }
  }
  private func checkAlerts(_ s: Snapshot) {
    let observation = ResourceObservation(date: s.date, duration: s.observedDuration, cpu: s.cpu,
      diskFree: s.diskTotal > 0 ? s.diskFree : nil,
      pressure: s.pressure == "Normal" ? 0 : ["Warning", "Elevated"].contains(s.pressure) ? 1 : s.pressure == "Critical" ? 2 : nil,
      swap: s.totalMemory > 0 ? s.swap : nil, temperature: s.cpuTemperature,
      apps: s.apps.filter { !$0.isSystem }.map { app in
        ResourceApp(id: app.id, name: app.name,
          identity: app.processes.min(by: { $0.start < $1.start }).map { "\($0.pid):\($0.start)" } ?? app.id,
          cpu: app.cpu / Double(max(1, s.cores)), memory: app.memory, write: app.write,
          network: s.networkAvailable ? app.download + app.upload : .nan)
      })
    _ = insightEngine.observe(observation, rules: insightRules)
    insights = insightEngine.findings
    for finding in ruleEngine.observe(observation, rules: alertRules) {
      alert(finding.id, title: finding.title, detail: finding.detail)
    }
  }
  private func alert(_ key: String, title: String, detail: String) {
    if let last = lastAlert[key], Date().timeIntervalSince(last) < 1800 { return }
    lastAlert[key] = Date()
    alerts.insert(MonitorAlert(title: title, detail: detail), at: 0)
    if alerts.count > 100 { alerts.removeLast() }
    if notifications && !quietHours.contains(Date()) {
      let content = UNMutableNotificationContent()
      content.title = title
      content.body = detail
      content.sound = .default
      UNUserNotificationCenter.current().add(
        UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
  }
  func exportCSV() {
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      "\(AppIdentity.exportName)-\(Date().formatted(.iso8601.year().month().day())) .csv".replacingOccurrences(
        of: " .", with: ".")
    panel.allowedContentTypes = [.commaSeparatedText]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    func quote(_ s: String) -> String {
      "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
    let rows = snapshot.apps.map { a -> String in
      let numeric = [a.cpu, a.memory, a.read, a.write, a.download, a.upload].map { String($0) }
      let gpu = a.gpu.map { String($0) } ?? ""
      let power = a.power.map { String($0) } ?? ""
      return ([quote(a.name), String(a.processes.count)] + numeric + [gpu, power]).joined(
        separator: ",")
    }
    let csv =
      "App,Processes,CPU percent of one core,Memory bytes,Disk read bytes/s,Disk write bytes/s,Download bytes/s,Upload bytes/s,GPU percent,Power watts\n"
      + rows.joined(separator: "\n")
    do { try csv.write(to: url, atomically: true, encoding: .utf8) } catch {
      message = error.localizedDescription
    }
  }
}
