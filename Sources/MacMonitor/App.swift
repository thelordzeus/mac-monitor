import AppKit
import CleanupCore
import Combine
import SwiftUI

struct MacMonitorApp: App {
  @NSApplicationDelegateAdaptor(MonitorAppDelegate.self) private var delegate
  @StateObject private var store = MonitorStore()
  var body: some Scene {
    WindowGroup(AppIdentity.name, id: "dashboard") {
      DashboardRoot(store: store, delegate: delegate)
    }.defaultSize(width: 1260, height: 890).windowStyle(.hiddenTitleBar)
      .commands {
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
  @Environment(\.openWindow) private var openWindow
  var body: some View {
    DashboardView(store: store).environmentObject(store).background(WindowSetup())
      .ignoresSafeArea(.container, edges: .top)
      .onAppear { delegate.attach(store, showWindow: { openWindow(id: "dashboard") }) }
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
    store?.flushHistory()
    store?.stopCleanup()
  }
  func applicationDidResignActive(_ notification: Notification) {
    if popover.isShown { popover.performClose(nil) }
  }
  func attach(_ store: MonitorStore, showWindow: @escaping () -> Void) {
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
      rootView: MenuDashboard(store: store, open: { [weak self] in self?.openWindow() }))
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
    item?.button?.title = parts.isEmpty ? "" : " " + parts.joined(separator: "  ")
    item?.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
  }
  @objc private func toggle() {
    guard let button = item?.button else { return }
    if popover.isShown {
      popover.performClose(nil)
    } else {
      popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }
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
  var open: () -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Label(AppIdentity.name, systemImage: "waveform.path.ecg").font(
          .system(size: 15, weight: .semibold))
        Spacer()
        Text("Up \(Format.duration(store.snapshot.uptime))").font(.system(size: 10))
          .foregroundStyle(Color.muted)
      }
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
      Divider()
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
