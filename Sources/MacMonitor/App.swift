import AppKit
import CleanupCore
import Combine
import SwiftUI

struct MacMonitorApp: App {
  @NSApplicationDelegateAdaptor(MonitorAppDelegate.self) private var delegate
  @StateObject private var store = MonitorStore()
  @StateObject private var updater = AppUpdater()
  var body: some Scene {
    WindowGroup(AppIdentity.name, id: "dashboard") {
      DashboardRoot(store: store, delegate: delegate, updater: updater)
    }.defaultSize(width: 1260, height: 890).windowStyle(.hiddenTitleBar)
      .commands {
        CommandGroup(after: .appInfo) {
          Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!updater.canCheckForUpdates)
        }
        CommandGroup(replacing: .appSettings) {
          Button("Settings…") { store.settingsVisible = true }.keyboardShortcut(",")
        }
        CommandMenu("Monitor") {
          Button(store.paused ? "Resume" : "Pause") { store.paused.toggle() }.keyboardShortcut(
            "p", modifiers: [.command, .shift])
          Button("Export App Stats…") { store.exportCSV() }.keyboardShortcut(
            "e", modifiers: [.command, .shift])
          Divider()
          ForEach(Array(MonitorTab.allCases.prefix(10).enumerated()), id: \.element.id) { i, tab in
            Button(tab.rawValue) { store.selectedTab = tab }.keyboardShortcut(
              KeyEquivalent(Character(String((i + 1) % 10))), modifiers: .command)
          }
          Button("Cleanup") { store.selectedTab = .cleanup }.keyboardShortcut(
            "k", modifiers: [.command, .shift])
        }
      }
  }
}
struct DashboardRoot: View {
  @ObservedObject var store: MonitorStore
  let delegate: MonitorAppDelegate
  @ObservedObject var updater: AppUpdater
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    DashboardView(store: store).environmentObject(store).environmentObject(updater)
      .background(WindowSetup())
      .ignoresSafeArea(.container, edges: .top)
      .onAppear {
        updater.start()
        delegate.attach(store, updater: updater, showWindow: { openWindow(id: "dashboard") })
      }
  }
}
struct WindowSetup: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        window.title = AppIdentity.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
          window.standardWindowButton(button)?.isHidden = true
        }
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Color.window)
        window.minSize = NSSize(width: 1080, height: 740)
        window.setFrameAutosaveName("MacMonitorDashboard")
      }
    }
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {}
}
final class MonitorAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
  private var item: NSStatusItem?
  private var metricItems: [MonitorTab: NSStatusItem] = [:]
  private var floatingPanel: NSPanel?
  private var popover = NSPopover()
  private var store: MonitorStore?
  private var subscription: AnyCancellable?
  private var cleanupSubscription: AnyCancellable?
  private var showWindow: (() -> Void)?
  private var outsideClickMonitor: Any?
  private var localClickMonitor: Any?
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationWillTerminate(_ notification: Notification) {
    stopDismissalMonitoring()
    floatingPanel?.orderOut(nil)
    store?.flushHistory()
    store?.stopCleanup()
  }
  func applicationDidResignActive(_ notification: Notification) {
    if popover.isShown { popover.performClose(nil) }
  }
  func attach(_ store: MonitorStore, updater: AppUpdater, showWindow: @escaping () -> Void) {
    self.showWindow = showWindow
    guard self.store == nil else { return }
    self.store = store
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item?.button?.target = self
    item?.button?.action = #selector(toggle)
    popover.behavior = .transient
    popover.delegate = self
    popover.contentSize = NSSize(width: 420, height: 580)
    popover.contentViewController = NSHostingController(
      rootView: MenuDashboard(
        store: store, updater: updater, open: { [weak self] in self?.openWindow() },
        checkForUpdates: { [weak self] in
          self?.popover.performClose(nil)
          updater.checkForUpdates()
        }))
    subscription = store.objectWillChange.debounce(for: .milliseconds(120), scheduler: RunLoop.main)
      .sink { [weak self] _ in self?.updateTitle() }
    cleanupSubscription = NotificationCenter.default.publisher(
      for: CleanupWorkspace.openNotification).receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.openWindow() }
    updateTitle()
  }
  private func updateTitle() {
    guard let store else { return }
    let s = store.snapshot
    var parts: [String] = []
    for tab in MonitorTab.allCases where store.menuMetrics.contains(tab) {
      switch tab {
      case .cpu: parts.append("\(Format.percent(s.cpu))")
      case .memory: parts.append(Format.memory(s.memoryUsed, decimals: 1))
      case .gpu: if let gpu = s.gpu { parts.append("G \(Format.percent(gpu))") }
      case .network: parts.append("↓ \(Format.rate(s.download,bits:store.networkBits))")
      case .disk: parts.append("↗ \(Format.rate(s.diskWrite))")
      case .battery: if s.battery.present { parts.append("\(Format.percent(s.battery.level))") }
      default: break
      }
    }
    item?.button?.image = NSImage(
      systemSymbolName: s.pressure == "Critical" ? "exclamationmark.triangle" : "waveform.path.ecg",
      accessibilityDescription: AppIdentity.name)
    item?.button?.imagePosition = .imageLeft
    let metrics = store.independentMenuItems ? store.menuMetrics.intersection([.cpu, .memory, .gpu, .network, .disk, .battery]) : []
    for tab in Array(metricItems.keys) where !metrics.contains(tab) {
      if let old = metricItems.removeValue(forKey: tab) { NSStatusBar.system.removeStatusItem(old) }
    }
    for tab in MonitorTab.allCases where metrics.contains(tab) {
      if metricItems[tab] == nil {
        let separate = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        separate.button?.target = self; separate.button?.action = #selector(toggleMetric(_:))
        separate.button?.tag = MonitorTab.allCases.firstIndex(of: tab) ?? 0
        metricItems[tab] = separate
      }
      let summary = Summary.make(tab, store: store)
      metricItems[tab]?.button?.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.rawValue)
      metricItems[tab]?.button?.imagePosition = .imageLeft
      metricItems[tab]?.button?.title = " " + summary.value + " " + summary.unit
      metricItems[tab]?.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
      metricItems[tab]?.button?.toolTip = "Mac Pulse · " + tab.rawValue
    }
    item?.button?.title = store.independentMenuItems || parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
    updateFloatingPanel()
    item?.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  }
  @objc private func toggle() {
    guard let button = item?.button else { return }
    showPopover(button, tab: nil)
  }
  @objc private func toggleMetric(_ button: NSStatusBarButton) {
    guard MonitorTab.allCases.indices.contains(button.tag) else { return }
    showPopover(button, tab: MonitorTab.allCases[button.tag])
  }
  private func showPopover(_ button: NSStatusBarButton, tab: MonitorTab?) {
    let closeOnly = popover.isShown && store?.menuPanelTab == tab
    popover.performClose(nil)
    guard !closeOnly else { return }
    store?.menuPanelTab = tab
    popover.contentSize = NSSize(width: 420, height: tab == nil ? 580 : 440)
    popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }
  private func updateFloatingPanel() {
    guard let store else { return }
    if !store.floatingDashboard { floatingPanel?.orderOut(nil); return }
    if floatingPanel == nil {
      let panel = NSPanel(contentRect: NSRect(x: 180, y: 180, width: 340, height: 230),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      panel.title = "Mac Pulse floating dashboard"
      panel.level = .floating; panel.isMovableByWindowBackground = true
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
      panel.isExcludedFromWindowsMenu = false
      panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = true
      panel.contentView = NSHostingView(rootView: FloatingDashboard(store: store, open: { [weak self] in self?.openWindow() }))
      panel.setFrameAutosaveName("MacPulseFloatingDashboard")
      panel.setFrameUsingName("MacPulseFloatingDashboard")
      floatingPanel = panel
    }
    if floatingPanel?.isVisible == false { floatingPanel?.orderFrontRegardless() }
  }
  func popoverDidShow(_ notification: Notification) {
    stopDismissalMonitoring()
    let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
    outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDown) { [weak self] _ in
      self?.popover.performClose(nil)
    }
    localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDown.union(.keyDown)) {
      [weak self] event in
      guard let self, self.popover.isShown else { return event }
      if event.type == .keyDown {
        if event.keyCode == 53 {
          self.popover.performClose(nil)
          return nil
        }
      } else if event.window !== self.popover.contentViewController?.view.window
        && event.window !== self.item?.button?.window
        && !self.metricItems.values.contains(where: { event.window === $0.button?.window })
      {
        self.popover.performClose(nil)
      }
      return event
    }
  }
  func popoverDidClose(_ notification: Notification) {
    stopDismissalMonitoring()
  }
  private func stopDismissalMonitoring() {
    if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    outsideClickMonitor = nil
    localClickMonitor = nil
  }
  private func openWindow() {
    popover.performClose(nil)
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.title == AppIdentity.name }) {
      window.makeKeyAndOrderFront(nil)
    } else {
      showWindow?()
    }
  }
}
struct MenuDashboard: View {
  @ObservedObject var store: MonitorStore
  @ObservedObject var updater: AppUpdater
  var open: () -> Void
  var checkForUpdates: @MainActor () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(AppIdentity.name, systemImage: "waveform.path.ecg").font(
          .system(size: 15, weight: .semibold))
        Spacer()
        Text("Up \(Format.duration(store.snapshot.uptime))").font(.system(size: 10))
          .foregroundStyle(Color.muted)
      }
      if let tab = store.menuPanelTab {
        MenuMetricDetail(store: store, tab: tab, open: open)
      } else {
      LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
        ForEach([MonitorTab.cpu, .memory, .gpu, .disk, .network, .battery]) { tab in
          let summary = Summary.make(tab, store: store)
          Button {
            store.selectedTab = tab
            open()
          } label: {
            VStack(alignment: .leading, spacing: 7) {
              Label(tab.rawValue, systemImage: tab.symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(tab.color)
              HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(summary.value).font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(summary.unit).font(.system(size: 11)).foregroundStyle(Color.muted)
              }
              HistoryChart(samples: store.liveSamples, tab: tab, bars: true).frame(height: 20)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(
              Color.surface, in: RoundedRectangle(cornerRadius: 13))
          }.buttonStyle(.plain)
        }
      }
      HStack {
        Text("Busiest Right Now").font(.system(size: 12, weight: .medium))
        Spacer()
        Text("CPU").font(.system(size: 10)).foregroundStyle(Color.muted)
      }
      ForEach(store.snapshot.apps.filter { !$0.isSystem }.sorted { $0.cpu > $1.cpu }.prefix(3)) {
        app in
        Button {
          store.selectedTab = .cpu
          store.openApp(app)
          open()
        } label: {
          HStack(spacing: 9) {
            AppIcon(image: app.icon, size: 21)
            Text(app.name).font(.system(size: 12))
            Spacer()
            Text(Format.percent(store.normalizedCPU(app.cpu), precise: true)).font(
              .system(size: 12)
            ).foregroundStyle(Color.muted)
          }
        }.buttonStyle(.plain)
      }
      }
      Divider()
      Button("Check for Updates…", action: checkForUpdates)
        .disabled(!updater.canCheckForUpdates)
        .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.muted)
      HStack {
        Button("Open Dashboard") {
          store.selectedTab = .overview
          open()
        }
        Button("Cleanup") {
          store.selectedTab = .cleanup
          open()
        }
        Spacer()
        Button("Settings") {
          store.settingsVisible = true
          open()
        }
        Button("Quit") { NSApp.terminate(nil) }
      }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Color.muted)
    }.padding(18).frame(width: 420).background(Color.window).preferredColorScheme(.dark)
  }
}
