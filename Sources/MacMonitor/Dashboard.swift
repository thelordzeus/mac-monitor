import AppKit
import SwiftUI

struct DashboardView: View {
  @ObservedObject var store: MonitorStore
  var exporting = false
  var body: some View {
    VStack(spacing: 0) {
      header
      if exporting {
        dashboardContent.frame(maxHeight: .infinity, alignment: .top).clipped()
      } else {
        ScrollView { dashboardContent }.scrollIndicators(.hidden)
      }
      footer
    }.background(Color.window).foregroundStyle(.white).environment(\.colorScheme, .dark)
      .preferredColorScheme(.dark)
      .frame(minWidth: 1080, minHeight: 740)
      .sheet(isPresented: $store.settingsVisible) { SettingsView(store: store) }
      .sheet(item: $store.selectedApp) { app in AppDetailView(store: store, app: app) }
      .sheet(isPresented: $store.alertsVisible) { AlertsView(store: store) }
      .alert(
        "Mac Monitor",
        isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })
      ) {
        Button("OK") { store.message = nil }
      } message: {
        Text(store.message ?? "")
      }
  }
  private var dashboardContent: some View {
    Group {
      switch store.selectedTab {
      case .overview: overview
      case .sound: SoundView(store: store, exporting: exporting)
      case .bluetooth: BluetoothView(store: store)
      case .projects: ProjectsView(store: store)
      default: metricDetail
      }
    }.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 20)
  }
  private var header: some View {
    HStack(spacing: 0) {
      WindowControls().frame(width: 88, alignment: .leading)
      HStack(spacing: 2) {
        ForEach(store.visibleTabs) { tab in
          Button {
            store.selectedTab = tab
            store.search = ""
          } label: {
            HStack(spacing: 7) {
              Image(systemName: tab.symbol).font(.system(size: 12))
              Text(tab.rawValue).font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(store.selectedTab == tab ? tab.color : Color.muted)
            .padding(.horizontal, 13).padding(.vertical, 10)
            .background(store.selectedTab == tab ? tab.color.opacity(0.16) : .clear, in: Capsule())
          }.buttonStyle(.plain).help("Show \(tab.rawValue)")
        }
      }.padding(4).background(Color.surface, in: Capsule())
      Spacer(minLength: 12)
    }.padding(.leading, 18).frame(height: 72)
  }
  private var footer: some View {
    HStack(spacing: 12) {
      Circle().fill(store.paused ? Color.orange : Color.green).frame(width: 5, height: 5)
      Text(store.paused ? "Paused" : "Live · \(Int(store.interval))s refresh").font(
        .system(size: 10))
      Text(
        "\(store.snapshot.processCount) processes · \(store.snapshot.gpuName) · Up \(Format.duration(store.snapshot.uptime))"
      ).font(.system(size: 10)).foregroundStyle(Color.muted)
      Spacer()
      if store.selectedTab != .sound && store.selectedTab != .bluetooth
        && store.selectedTab != .projects
      {
        HStack(spacing: 4) {
          ForEach(HistoryRange.allCases, id: \.self) { range in
            Button {
              store.historyRange = range
            } label: {
              Text(range.rawValue).font(.system(size: 10, weight: .medium)).padding(.horizontal, 7)
                .padding(.vertical, 4).background(
                  store.historyRange == range ? Color.white.opacity(0.09) : .clear,
                  in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain).foregroundStyle(store.historyRange == range ? .white : Color.muted)
          }
        }
      }
      Divider().frame(height: 12)
      Button {
        store.paused.toggle()
      } label: {
        Image(systemName: store.paused ? "play.fill" : "pause.fill")
      }.help(store.paused ? "Resume monitoring" : "Pause monitoring")
      Button {
        store.alertsVisible = true
      } label: {
        Image(systemName: store.alerts.isEmpty ? "bell" : "bell.badge")
      }.help("Activity alerts")
      if exporting {
        Image(systemName: "square.and.arrow.up").frame(width: 20)
      } else {
        Menu {
          Button("Save Dashboard Image…") { exportDashboard() }
          Button("Copy Dashboard") { exportDashboard(copy: true) }
          Button("Export App Stats as CSV…") { store.exportCSV() }
        } label: {
          Image(systemName: "square.and.arrow.up")
        }.menuStyle(.borderlessButton).frame(width: 20).help("Export")
      }
      Button {
        store.settingsVisible = true
      } label: {
        Image(systemName: "gearshape")
      }.help("Settings")
    }.buttonStyle(.plain).foregroundStyle(Color.muted).padding(.horizontal, 26).frame(height: 35)
      .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.035)).frame(height: 1) }
  }
  private var overview: some View {
    let s = store.snapshot
    return VStack(spacing: 18) {
      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18
      ) {
        ForEach(
          [MonitorTab.cpu, .memory, .gpu, .disk, .network, .battery].filter {
            !store.hiddenCards.contains($0)
          }
        ) { tab in
          OverviewCard(store: store, tab: tab).onTapGesture { store.selectedTab = tab }.help(
            "Open \(tab.rawValue) details")
        }
      }
      HStack(spacing: 18) {
        BreakdownCard(
          title: "Memory by Type", tab: .cpu,
          center: Format.percent(s.memoryUsed / max(1, s.totalMemory) * 100), subtitle: "in use",
          slices: [
            RingSlice(name: "App", value: s.appMemory, color: .cpuBlue),
            RingSlice(name: "Wired", value: s.wired, color: Color(hex: 0xe76529)),
            RingSlice(name: "Compressed", value: s.compressed, color: MonitorTab.network.color),
            RingSlice(name: "Cached", value: s.cached, color: .gray),
            RingSlice(
              name: "Free", value: max(0, s.totalMemory - s.memoryUsed - s.cached),
              color: Color(hex: 0x313136)),
          ])
        BreakdownCard(
          title: "Memory by App", tab: .memory, center: Format.memory(appTotalMemory),
          subtitle: "all apps", slices: appSlices(power: false))
        BreakdownCard(
          title: "Power by App", tab: .battery, center: Format.watts(appTotalPower),
          subtitle: "all apps", slices: appSlices(power: true), bytes: false)
      }
      if s.cpuTemperature != nil || s.gpuTemperature != nil || !s.fans.isEmpty {
        HStack(spacing: 24) {
          Label("CPU \(store.temperature(s.cpuTemperature))", systemImage: "thermometer.medium")
          Label("GPU \(store.temperature(s.gpuTemperature))", systemImage: "square.3.layers.3d")
          if !s.fans.isEmpty {
            Label(
              "Fans \(s.fans.map { String(format:"%.0f rpm",$0) }.joined(separator:" · "))",
              systemImage: "fan")
          }
          Spacer()
          Text("Thermal state: \(thermalState)")
        }.font(.system(size: 11)).foregroundStyle(Color.muted).padding(.horizontal, 10)
      }
    }
  }
  private var thermalState: String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "Normal"
    case .fair: return "Warm"
    case .serious: return "Hot"
    case .critical: return "Critical"
    @unknown default: return "Unknown"
    }
  }
  private var appTotalMemory: Double { store.snapshot.apps.reduce(0) { $0 + $1.memory } }
  private var appTotalPower: Double? {
    let a = store.snapshot.apps.compactMap(\.power)
    return a.isEmpty ? nil : a.reduce(0, +)
  }
  private func appSlices(power: Bool) -> [RingSlice] {
    let apps = store.snapshot.apps.filter { !$0.isSystem }.sorted {
      power ? ($0.power ?? 0) > ($1.power ?? 0) : $0.memory > $1.memory
    }
    let color = power ? MonitorTab.battery.color : MonitorTab.memory.color
    var slices = apps.prefix(4).enumerated().map { i, a in
      RingSlice(
        name: a.name, value: power ? a.power ?? 0 : a.memory,
        color: color.opacity(1 - Double(i) * 0.16), icon: a.icon)
    }
    let total = power ? appTotalPower ?? 0 : appTotalMemory
    slices.append(
      RingSlice(
        name: "Other", value: max(0, total - slices.reduce(0) { $0 + $1.value }),
        color: Color(hex: 0x363639)))
    return slices
  }
  private var metricDetail: some View {
    let tab = store.selectedTab
    return VStack(spacing: 18) {
      hero(tab)
      HStack(spacing: 18) {
        ForEach(Array(detailCards(tab).enumerated()), id: \.offset) { _, card in
          SmallStatCard(card: card, color: tab.color)
        }
      }
      appTable(tab)
    }
  }
  private func hero(_ tab: MonitorTab) -> some View {
    let s = store.snapshot
    let summary = Summary.make(tab, store: store)
    return HStack(spacing: 24) {
      VStack(alignment: .leading, spacing: 10) {
        Text(summary.caption).font(.system(size: 14)).foregroundStyle(Color.muted)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(summary.value).font(.system(size: 51, weight: .bold, design: .rounded))
          Text(summary.unit).font(.system(size: 22, weight: .semibold)).foregroundStyle(Color.muted)
        }.lineLimit(1).minimumScaleFactor(0.65)
        if tab == .memory {
          StatusPill(
            title: s.pressure, color: s.pressure == "Normal" ? MonitorTab.battery.color : .orange,
            symbol: s.pressure == "Normal" ? "checkmark" : "exclamationmark")
        }
        Spacer()
        ForEach(summary.facts, id: \.0) { label, value in
          HStack {
            Text(label).foregroundStyle(Color.muted)
            Spacer()
            Text(value).fontWeight(.semibold)
          }.font(.system(size: 13))
        }
      }.frame(width: 196, alignment: .leading)
      VStack(spacing: 8) {
        HistoryChart(samples: store.chartSamples, tab: tab, maximum: chartMaximum(tab)).frame(
          height: 166)
        HStack {
          Text(
            store.historyRange == .live ? "Last two minutes" : "Last \(store.historyRange.rawValue)"
          )
          Spacer()
          Text(
            store.chartSamples.last.map {
              Date(timeIntervalSince1970: $0.timestamp).formatted(date: .omitted, time: .standard)
            } ?? "Waiting for samples")
        }.font(.system(size: 9)).foregroundStyle(Color.muted.opacity(0.7))
      }.frame(maxWidth: .infinity)
    }.padding(24).frame(height: 234).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 23))
  }
  private func chartMaximum(_ tab: MonitorTab) -> Double? {
    switch tab {
    case .cpu, .gpu, .battery: return 100
    case .memory: return store.snapshot.totalMemory
    default: return nil
    }
  }
  private func detailCards(_ tab: MonitorTab) -> [StatCardData] {
    let s = store.snapshot
    let top = store.apps.first
    let topCard = StatCardData(
      title: "Top App", symbol: "square.grid.2x2", value: top?.name ?? "—",
      subtitle: top.map { store.value($0, tab: tab) } ?? "", icon: top?.icon, app: top)
    switch tab {
    case .cpu:
      return [
        StatCardData(
          title: "User", symbol: "cpu", value: Format.percent(s.user), subtitle: "Your apps"),
        StatCardData(
          title: "System", symbol: "cpu", value: Format.percent(s.system), subtitle: "macOS"),
        StatCardData(
          title: "Cores", symbol: "bolt", value: "\(s.cores)",
          subtitle: s.performanceCores > 0
            ? "\(s.performanceCores) P   \(s.efficiencyCores) E" : "Logical processors"), topCard,
      ]
    case .memory:
      return [
        StatCardData(
          title: "App", symbol: "square.grid.2x2", value: Format.memory(s.appMemory),
          progress: s.appMemory / max(1, s.totalMemory)),
        StatCardData(
          title: "Wired", symbol: "lock", value: Format.memory(s.wired),
          progress: s.wired / max(1, s.totalMemory)),
        StatCardData(
          title: "Compressed", symbol: "memorychip", value: Format.memory(s.compressed),
          progress: s.compressed / max(1, s.totalMemory)), topCard,
      ]
    case .disk:
      return [
        StatCardData(title: "Reading", symbol: "arrow.down", value: Format.rate(s.diskRead)),
        StatCardData(title: "Writing", symbol: "arrow.up", value: Format.rate(s.diskWrite)),
        StatCardData(
          title: "Volumes", symbol: "internaldrive", value: "\(s.volumes.count)",
          subtitle: s.volumes.joined(separator: " · ")), topCard,
      ]
    case .network:
      return [
        StatCardData(
          title: "Uploading", symbol: "arrow.up",
          value: Format.rate(s.upload, bits: store.networkBits)),
        StatCardData(
          title: "Last 7 Days", symbol: "chart.bar",
          value: Format.bytes(store.week.download + store.week.upload)),
        StatCardData(
          title: "Interface", symbol: s.interfaceType == "Wi-Fi" ? "wifi" : "network",
          value: s.interfaceType, subtitle: s.interface), topCard,
      ]
    case .gpu:
      return [
        StatCardData(
          title: "Memory", symbol: "memorychip", value: s.gpuMemory.map { Format.memory($0) } ?? "—"
        ),
        StatCardData(title: "Average", symbol: "chart.bar", value: Format.percent(average(.gpu))),
        StatCardData(
          title: "Peak", symbol: "bolt",
          value: Format.percent(store.liveSamples.compactMap(\.gpu).max() ?? 0)), topCard,
      ]
    case .battery:
      return [
        StatCardData(title: "Power Draw", symbol: "bolt", value: Format.watts(s.battery.watts)),
        StatCardData(
          title: "Health", symbol: "battery.100percent",
          value: s.battery.health.map { Format.percent($0) } ?? "—",
          progress: s.battery.health.map { $0 / 100 }),
        StatCardData(
          title: "Temperature", symbol: "thermometer.medium",
          value: store.temperature(s.battery.temperature)), topCard,
      ]
    default: return []
    }
  }
  private func average(_ tab: MonitorTab) -> Double {
    let values = store.chartSamples.map { $0.value(tab) }
    return values.reduce(0, +) / Double(max(1, values.count))
  }
  private func appTable(_ tab: MonitorTab) -> some View {
    VStack(spacing: 0) {
      HStack {
        Text("App").foregroundStyle(Color.muted)
        Spacer()
        if !exporting {
          Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(Color.muted)
          TextField("Search apps", text: $store.search).textFieldStyle(.plain).font(.system(size: 11))
            .frame(width: 110)
          Toggle("System", isOn: $store.showSystem).toggleStyle(.checkbox).font(.system(size: 10))
            .foregroundStyle(Color.muted)
        }
        Text(
          tab == .disk
            ? "Writing" : tab == .network ? "Downloading" : tab == .battery ? "Power" : tab.rawValue
        ).foregroundStyle(Color.muted).frame(width: 115, alignment: .trailing)
      }.font(.system(size: 13)).padding(.horizontal, 15).padding(.top, 16).padding(.bottom, 10)
      if store.apps.isEmpty {
        EmptyState(
          symbol: "magnifyingglass", title: "No matching apps",
          detail: "Try another search or include system processes."
        ).frame(height: 220)
      }
      ForEach(Array(store.apps.prefix(exporting ? 5 : 80).enumerated()), id: \.element.id) {
        index, app in
        AppTableRow(
          store: store, app: app, tab: tab, highlighted: index == 0,
          maximum: store.apps.map { $0.value(for: tab) }.max() ?? 1)
      }
      if tab == .network && !store.snapshot.networkAvailable {
        Text("Per-app network counters are unavailable. System traffic is still monitored.").font(
          .system(size: 11)
        ).foregroundStyle(Color.muted).padding(12)
      }
      if tab == .gpu {
        Text(
          "Per-app GPU time is measured from Metal driver counters; overlapping work can exceed 100%."
        ).font(.system(size: 10)).foregroundStyle(Color.muted).padding(10)
      }
      if tab == .battery {
        Text(
          "Per-app power is the CPU energy reported by macOS. It does not include the display or all device power."
        ).font(.system(size: 10)).foregroundStyle(Color.muted).padding(10)
      }
    }.padding(.horizontal, 7).padding(.bottom, 10).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 23))
  }
  private func exportDashboard(copy: Bool = false) {
    let renderer = ImageRenderer(
      content: DashboardView(store: store, exporting: true).environmentObject(store).frame(
        width: 1260, height: 890))
    renderer.scale = 2
    renderer.colorMode = .nonLinear
    guard let cgImage = DashboardImage.render(renderer),
      let png = DashboardImage.png(cgImage)
    else { return }
    if copy {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.writeObjects([NSImage(cgImage: cgImage, size: .zero)])
      return
    }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "Mac-Monitor.png"
    panel.allowedContentTypes = [.png]
    if panel.runModal() == .OK, let url = panel.url {
      do { try png.write(to: url) } catch { store.message = error.localizedDescription }
    }
  }
}

extension Color { static let cpuBlue = MonitorTab.cpu.color }
struct WindowControls: View {
  @State private var hover = false
  var body: some View {
    HStack(spacing: 8) {
      control(Color(hex: 0xff5f57), symbol: "xmark", action: { NSApp.keyWindow?.performClose(nil) })
      control(Color(hex: 0xfebc2e), symbol: "minus", action: { NSApp.keyWindow?.miniaturize(nil) })
      control(
        Color(hex: 0x28c840), symbol: "arrow.up.left.and.arrow.down.right",
        action: { NSApp.keyWindow?.toggleFullScreen(nil) })
    }.onHover { hover = $0 }
  }
  private func control(_ color: Color, symbol: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Circle().fill(color).frame(width: 12, height: 12).overlay {
        if hover {
          Image(systemName: symbol).font(.system(size: 6, weight: .bold)).foregroundStyle(
            .black.opacity(0.65))
        }
      }
    }.buttonStyle(.plain).help(
      symbol == "xmark" ? "Close window" : symbol == "minus" ? "Minimize" : "Full screen")
  }
}
struct Summary {
  var caption: String
  var value: String
  var unit: String
  var facts: [(String, String)]
  static func make(_ tab: MonitorTab, store: MonitorStore) -> Summary {
    let s = store.snapshot
    func split(_ str: String) -> (String, String) {
      let parts = str.split(separator: " ")
      return (String(parts.first ?? "—"), parts.dropFirst().joined(separator: " "))
    }
    switch tab {
    case .cpu:
      return Summary(
        caption: "Now", value: String(format: "%.0f", s.cpu), unit: "%",
        facts: [
          (
            "Average today",
            Format.percent(
              store.today.averageCPU > 0
                ? store.today.averageCPU
                : store.liveSamples.map(\.cpu).reduce(0, +)
                  / Double(max(1, store.liveSamples.count)))
          ), ("Load", String(format: "%.2f", s.load)),
        ])
    case .memory:
      let v = split(Format.memory(s.memoryUsed))
      return Summary(
        caption: "In use of \(Format.memory(s.totalMemory,decimals:0))", value: v.0, unit: v.1,
        facts: [("Free", Format.memory(s.free)), ("Swap", Format.memory(s.swap))])
    case .disk:
      let v = split(Format.bytes(s.diskFree))
      return Summary(
        caption: "Free of \(Format.bytes(s.diskTotal))", value: v.0, unit: v.1,
        facts: [
          ("Used", Format.bytes(s.diskTotal - s.diskFree)),
          ("Written today", Format.bytes(store.today.written)),
        ])
    case .network:
      let v = split(Format.rate(s.download, bits: store.networkBits))
      return Summary(
        caption: "Downloading", value: v.0, unit: v.1,
        facts: [
          ("Today", Format.bytes(store.today.download + store.today.upload)),
          ("Last 30 days", Format.bytes(store.month.download + store.month.upload)),
        ])
    case .gpu:
      let gpu = store.liveSamples.compactMap(\.gpu)
      return Summary(
        caption: s.gpuName, value: s.gpu.map { String(format: "%.0f", $0) } ?? "—", unit: "%",
        facts: [
          ("Average", gpu.isEmpty ? "—" : Format.percent(gpu.reduce(0, +) / Double(gpu.count))),
          ("Peak", gpu.max().map { Format.percent($0) } ?? "—"),
        ])
    case .battery:
      return Summary(
        caption: s.battery.status,
        value: s.battery.present ? String(format: "%.0f", s.battery.level) : "—",
        unit: s.battery.present ? "%" : "",
        facts: [
          (
            s.battery.charging ? "Until full" : "Remaining",
            s.battery.remaining.map { Format.duration($0) }
              ?? (!s.battery.present
                ? "Not installed" : s.battery.plugged ? "AC Power" : "Calculating…")
          ), ("Cycles", s.battery.cycles.map(String.init) ?? "—"),
        ])
    default: return Summary(caption: "", value: "", unit: "", facts: [])
    }
  }
}
struct OverviewCard: View {
  @ObservedObject var store: MonitorStore
  var tab: MonitorTab
  @State private var hovered = false
  var body: some View {
    let s = store.snapshot
    let summary = Summary.make(tab, store: store)
    return VStack(alignment: .leading, spacing: 13) {
      HStack {
        LabelBadge(title: tab.rawValue, symbol: tab.symbol, color: tab.color)
        Spacer()
        Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(
          Color.muted.opacity(0.6))
      }
      VStack(alignment: .leading, spacing: 6) {
        Text(summary.caption).font(.system(size: 12)).foregroundStyle(Color.muted)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(summary.value).font(.system(size: 37, weight: .bold, design: .rounded))
          Text(summary.unit).font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.muted)
          Spacer(minLength: 0)
          if tab == .memory {
            StatusPill(title: s.pressure,
              color: s.pressure == "Normal" ? MonitorTab.battery.color : .orange,
              symbol: s.pressure == "Normal" ? "checkmark" : "exclamationmark")
          }
        }.lineLimit(1).minimumScaleFactor(0.6)
      }
      HStack(spacing: 8) {
        ForEach(facts, id: \.0) { label, value in
          VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(Color.muted).lineLimit(1)
            Text(value).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(
              0.6)
          }.frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      HistoryChart(
        samples: store.liveSamples, tab: tab,
        maximum: tab == .memory ? s.totalMemory : [.cpu, .gpu, .battery].contains(tab) ? 100 : nil,
        bars: true
      ).frame(height: 40).padding(.horizontal, 6).padding(.top, 4).background(
        tab.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 11))
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).frame(height: 244).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 22)
    ).overlay {
      RoundedRectangle(cornerRadius: 22).stroke(tab.color.opacity(hovered ? 0.3 : 0), lineWidth: 1)
    }.onHover { hovered = $0 }
  }
  private var facts: [(String, String)] {
    let s = store.snapshot
    switch tab {
    case .cpu:
      return [
        ("User", Format.percent(s.user)), ("System", Format.percent(s.system)),
        (
          "Average Today",
          Format.percent(store.today.averageCPU > 0 ? store.today.averageCPU : s.cpu)
        ),
      ]
    case .memory:
      return [
        ("App", Format.memory(s.appMemory)), ("Wired", Format.memory(s.wired)),
        ("Compressed", Format.memory(s.compressed)),
      ]
    case .gpu:
      return [
        ("Memory", s.gpuMemory.map { Format.memory($0) } ?? "—"),
        ("Average", Summary.make(.gpu, store: store).facts[0].1),
        ("Peak", Summary.make(.gpu, store: store).facts[1].1),
      ]
    case .disk:
      return [
        ("Reading", Format.rate(s.diskRead)), ("Writing", Format.rate(s.diskWrite)),
        ("Written Today", Format.bytes(store.today.written)),
      ]
    case .network:
      return [
        ("Uploading", Format.rate(s.upload, bits: store.networkBits)),
        ("Today", Format.bytes(store.today.download + store.today.upload)),
        ("Last 7 Days", Format.bytes(store.week.download + store.week.upload)),
      ]
    case .battery:
      return [
        ("Remaining", s.battery.remaining.map { Format.duration($0) } ?? "—"),
        ("Power Draw", Format.watts(s.battery.watts)),
        ("Health", s.battery.health.map { Format.percent($0) } ?? "—"),
      ]
    default: return []
    }
  }
}
struct StatCardData {
  var title: String
  var symbol: String
  var value: String
  var subtitle: String = ""
  var progress: Double?
  var icon: NSImage?
  var app: AppStat?
}
struct SmallStatCard: View {
  var card: StatCardData
  var color: Color
  @EnvironmentObject private var store: MonitorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 13) {
      LabelBadge(title: card.title, symbol: card.symbol, color: color, coloredTitle: false)
      HStack(spacing: 8) {
        if card.app != nil { AppIcon(image: card.icon, size: 22) }
        Text(card.value).font(.system(size: card.app != nil ? 17 : 24, weight: .semibold))
          .lineLimit(1).minimumScaleFactor(0.65)
      }
      if let progress = card.progress {
        GaugeBar(value: progress, maximum: 1, color: color)
      } else if !card.subtitle.isEmpty {
        HStack {
          Text(card.subtitle).font(.system(size: 12)).foregroundStyle(
            card.app != nil ? .white : Color.muted)
          Spacer()
          if card.app != nil {
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Color.muted)
          }
        }.lineLimit(1)
      }
      Spacer(minLength: 0)
    }.padding(17).frame(maxWidth: .infinity, alignment: .leading).frame(height: 128).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 22)
    ).onTapGesture { if let app = card.app { store.openApp(app) } }
  }
}
struct AppTableRow: View {
  @ObservedObject var store: MonitorStore
  var app: AppStat
  var tab: MonitorTab
  var highlighted: Bool
  var maximum: Double
  @State private var hover = false
  var body: some View {
    Button {
      store.openApp(app)
    } label: {
      HStack(spacing: 15) {
        AppIcon(image: app.icon)
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 5) {
            Text(app.name).font(.system(size: 16, weight: .semibold))
            if store.pinnedApps.contains(app.id) {
              Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(tab.color)
            }
          }
          Text("\(app.processes.count) \(app.processes.count == 1 ? "process" : "processes")").font(
            .system(size: 12)
          ).foregroundStyle(Color.muted)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 9) {
          Text(store.value(app, tab: tab)).font(.system(size: 16, weight: .semibold))
            .monospacedDigit()
          GaugeBar(value: app.value(for: tab), maximum: maximum, color: tab.color).frame(width: 184)
        }
      }.padding(.horizontal, 16).frame(height: 64).background(
        highlighted || hover ? Color.window : .clear, in: RoundedRectangle(cornerRadius: 14)
      ).contentShape(Rectangle())
    }.buttonStyle(.plain).foregroundStyle(.white).onHover { hover = $0 }.contextMenu {
      Button(store.pinnedApps.contains(app.id) ? "Unpin" : "Pin to Top") {
        if store.pinnedApps.contains(app.id) {
          store.pinnedApps.remove(app.id)
        } else {
          store.pinnedApps.insert(app.id)
        }
        store.saveLayout()
      }
      Button("Show Processes") { store.openApp(app) }
      if let path = app.bundlePath {
        Button("Reveal in Finder") {
          NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        }
      }
    }
  }
}
struct EmptyState: View {
  var symbol: String
  var title: String
  var detail: String
  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(
        Color.muted.opacity(0.7))
      Text(title).font(.system(size: 17, weight: .medium))
      Text(detail).font(.system(size: 12)).foregroundStyle(Color.muted).multilineTextAlignment(
        .center
      ).frame(maxWidth: 400)
    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
  }
}
