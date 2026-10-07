import AppKit
import ServiceManagement
import SwiftUI

struct SoundView: View {
  @ObservedObject var store: MonitorStore
  @ObservedObject var audio: AudioController
  var exporting: Bool
  init(store: MonitorStore, exporting: Bool = false) {
    self.store = store
    audio = store.audio
    self.exporting = exporting
  }
  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 20) {
        Image(systemName: "speaker.wave.2").font(.system(size: 20)).foregroundStyle(
          MonitorTab.sound.color
        ).frame(width: 44, height: 44).background(
          MonitorTab.sound.color.opacity(0.16), in: RoundedRectangle(cornerRadius: 13))
        VStack(alignment: .leading, spacing: 5) {
          Text("Output").font(.system(size: 16, weight: .semibold))
          if exporting {
            HStack(spacing: 5) {
              Text(audio.outputName)
              Image(systemName: "chevron.down").font(.system(size: 9))
            }.font(.system(size: 13)).foregroundStyle(Color.muted)
              .frame(width: 225, alignment: .leading)
          } else {
            Menu {
              ForEach(audio.devices) { device in
                Button(device.name) {
                  audio.selectOutput(device.id)
                  audio.refresh(apps: store.snapshot.apps, force: true)
                }
              }
            } label: {
              Text(audio.outputName).font(.system(size: 13)).foregroundStyle(Color.muted)
            }
            .menuStyle(.borderlessButton).frame(width: 225, alignment: .leading)
          }
        }
        Image(systemName: "speaker.wave.2").font(.system(size: 12)).foregroundStyle(Color.muted)
        VolumeSlider(
          value: Binding(get: { audio.volume }, set: { audio.setVolume($0) }),
          enabled: audio.volumeSupported)
        Text(audio.volumeSupported ? Format.percent(audio.volume * 100) : "Fixed").font(
          .system(size: 16, weight: .semibold)
        )
        .monospacedDigit().frame(width: 55, alignment: .trailing)
      }.padding(22).background(Color.surface, in: RoundedRectangle(cornerRadius: 23))
      VStack(spacing: 0) {
        HStack {
          Text("APP")
          Spacer()
          Text("STATUS").frame(width: 100, alignment: .leading)
          Text("VOLUME").frame(width: 300, alignment: .leading)
          Text("LEVEL").frame(width: 65, alignment: .trailing)
        }.font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(Color.muted)
          .padding(.bottom, 20)
        if audio.apps.isEmpty {
          EmptyState(
            symbol: "speaker.slash", title: "No audio apps yet",
            detail:
              "Open Music, a browser, or another app that plays audio. It will appear here automatically."
          ).frame(height: 350)
        }
        ForEach(
          Array(
            audio.apps.filter { row in
              store.showSystem
                || store.snapshot.apps.first(where: { $0.id == row.id }).map {
                  !$0.isSystem && $0.bundlePath?.hasPrefix("/System/Library") != true
                } == true
            }.prefix(exporting ? 8 : 80))
        ) { app in
          HStack(spacing: 14) {
            AppIcon(image: app.icon, size: 23)
            Text(app.name).font(.system(size: 16))
            Spacer()
            Text(app.playing ? "Playing" : "Silent").font(.system(size: 13)).foregroundStyle(
              Color.muted
            ).frame(width: 100, alignment: .leading)
            Button {
              audio.setGain(app, (audio.gains[app.id] ?? 1) == 0 ? 1 : 0)
            } label: {
              Image(
                systemName: (audio.gains[app.id] ?? 1) == 0 ? "speaker.slash" : "speaker.wave.2"
              ).font(.system(size: 11)).foregroundStyle(
                (audio.gains[app.id] ?? 1) == 0 ? .red : Color.muted)
            }.buttonStyle(.plain).help("Mute or unmute \(app.name)")
            VolumeSlider(
              value: Binding(get: { audio.gains[app.id] ?? 1 }, set: { audio.setGain(app, $0) })
            ).frame(width: 275)
            Text(
              (audio.gains[app.id] ?? 1) == 0
                ? "Muted" : Format.percent((audio.gains[app.id] ?? 1) * 100)
            ).font(.system(size: 14)).monospacedDigit().frame(width: 65, alignment: .trailing)
          }.frame(height: 47)
        }
        Spacer(minLength: 30)
        HStack {
          Text("App mixing uses macOS audio access. Audio is processed in memory.").font(
            .system(size: 11)
          ).foregroundStyle(Color.muted)
          Spacer()
          Button("Reset Volumes") { audio.reset() }.buttonStyle(.plain).foregroundStyle(
            MonitorTab.sound.color
          ).font(.system(size: 12))
        }
      }.padding(22).frame(minHeight: 570).background(
        Color.surface, in: RoundedRectangle(cornerRadius: 23))
    }.onAppear { audio.refresh(apps: store.snapshot.apps, force: true) }
      .alert(
        "Sound",
        isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })
      ) {
        Button("OK") { audio.error = nil }
        Button("Open Privacy Settings") {
          NSWorkspace.shared.open(
            URL(
              string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
            )!)
        }
      } message: {
        Text(audio.error ?? "")
      }
  }
}
struct BluetoothView: View {
  @ObservedObject var store: MonitorStore
  @ObservedObject var bluetooth: BluetoothController
  init(store: MonitorStore) {
    self.store = store
    bluetooth = store.bluetooth
  }
  var body: some View {
    let connected = bluetooth.devices.filter(\.connected)
    let lowest = connected.flatMap(\.levels).map(\.1).min()
    return VStack(spacing: 18) {
      HStack(spacing: 19) {
        Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 22))
          .foregroundStyle(MonitorTab.bluetooth.color).frame(width: 44, height: 44).background(
            MonitorTab.bluetooth.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
        VStack(alignment: .leading, spacing: 6) {
          Text(bluetooth.enabled ? "\(connected.count) connected" : "Bluetooth devices").font(
            .system(size: 17, weight: .semibold))
          Text(
            bluetooth.loading
              ? "Reading connected devices…"
              : lowest.map { "Lowest device battery: \($0)%" }
                ?? "Battery levels appear when a device reports them to macOS."
          ).font(.system(size: 13)).foregroundStyle(Color.muted)
        }
        Spacer()
        if let lowest {
          GaugeBar(value: Double(lowest), maximum: 100, color: lowest < 20 ? .red : .orange).frame(
            width: 70)
          Text("\(lowest)%").font(.system(size: 16, weight: .semibold))
        }
        Button("Bluetooth Settings ↗") {
          NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        }.buttonStyle(.plain).foregroundStyle(MonitorTab.bluetooth.color)
        Button {
          bluetooth.refresh()
        } label: {
          Image(systemName: "arrow.clockwise")
        }.buttonStyle(.plain).disabled(bluetooth.loading).help("Refresh devices")
      }.padding(22).background(Color.surface, in: RoundedRectangle(cornerRadius: 23))
      VStack(spacing: 0) {
        HStack {
          Text("DEVICE")
          Spacer()
          Text("KIND").frame(width: 150, alignment: .leading)
          Text("BATTERY").frame(width: 200, alignment: .leading)
          Text("LEVEL").frame(width: 65, alignment: .trailing)
        }.font(.system(size: 11, weight: .semibold)).tracking(1).foregroundStyle(Color.muted)
          .padding(.bottom, 20)
        if !bluetooth.enabled {
          EmptyState(
            symbol: "headphones", title: "See your connected devices",
            detail: "Read paired devices and battery levels from this Mac."
          ).frame(height: 200)
          Button("Read Bluetooth Devices") { bluetooth.refresh() }
            .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(.white).background(MonitorTab.bluetooth.color, in: Capsule())
        } else if bluetooth.loading && bluetooth.devices.isEmpty {
          ProgressView().frame(height: 250)
        } else if bluetooth.devices.isEmpty {
          EmptyState(
            symbol: "headphones", title: "No devices found",
            detail: bluetooth.error ?? "Pair or connect a Bluetooth device, then refresh."
          ).frame(height: 300)
        }
        ForEach(bluetooth.devices) { d in
          VStack(spacing: 0) {
            HStack(spacing: 15) {
              Image(systemName: d.symbol).font(.system(size: 14)).foregroundStyle(
                MonitorTab.bluetooth.color
              ).frame(width: 28, height: 28).background(
                MonitorTab.bluetooth.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
              Text(d.name).font(.system(size: 16))
              if !d.connected { StatusPill(title: "Paired · away", color: .gray) }
              Spacer()
              Text(d.kind).font(.system(size: 13)).foregroundStyle(Color.muted).frame(
                width: 150, alignment: .leading)
              if d.levels.count == 1 {
                GaugeBar(
                  value: Double(d.levels[0].1), maximum: 100, color: MonitorTab.bluetooth.color
                ).frame(width: 170)
                Text("\(d.levels[0].1)%").frame(width: 65, alignment: .trailing)
              } else {
                Text(d.levels.isEmpty ? "Not reported" : "").font(.system(size: 12))
                  .foregroundStyle(Color.muted).frame(width: 249, alignment: .trailing)
              }
            }.frame(height: 46)
            if d.levels.count > 1 {
              ForEach(d.levels, id: \.0) { label, value in
                HStack {
                  Text(label).font(.system(size: 14)).foregroundStyle(Color.muted).padding(
                    .leading, 44)
                  Spacer()
                  GaugeBar(value: Double(value), maximum: 100, color: MonitorTab.bluetooth.color)
                    .frame(width: 170)
                  Text("\(value)%").frame(width: 65, alignment: .trailing)
                }.frame(height: 36)
              }
            }
          }
        }
        Spacer(minLength: 30)
      }.padding(22).frame(minHeight: 570).background(
        Color.surface, in: RoundedRectangle(cornerRadius: 23))
    }
  }
}
struct ProjectsView: View {
  @ObservedObject var store: MonitorStore
  @State private var pending: [ProcessStat] = []
  @State private var confirm = false
  @State private var name = ""
  private var idle: [ProjectStat] {
    store.snapshot.projects.filter {
      !$0.ports.isEmpty && $0.idleSince.map { Date().timeIntervalSince($0) >= 60 } == true
    }
  }
  var body: some View {
    VStack(spacing: 12) {
      if !idle.isEmpty {
        HStack(spacing: 14) {
          Image(systemName: "moon").foregroundStyle(MonitorTab.projects.color).frame(
            width: 28, height: 28
          ).background(
            MonitorTab.projects.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
          VStack(alignment: .leading, spacing: 5) {
            Text("\(idle.count) dev servers are running but idle").font(
              .system(size: 16, weight: .semibold))
            Text(
              "Stopping them frees \(Format.memory(idle.reduce(0) { $0+$1.memory })) and ports \(idle.flatMap(\.ports).map(String.init).joined(separator:", "))."
            ).font(.system(size: 13)).foregroundStyle(Color.muted)
          }
          Spacer()
          Button("Stop All…") {
            pending = idle.flatMap(\.processes)
            name = "\(idle.count) idle projects"
            confirm = true
          }.buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 9)
            .foregroundStyle(.white).background(MonitorTab.projects.color, in: Capsule())
        }.padding(18).background(
          MonitorTab.projects.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
      } else {
        HStack {
          Label("\(store.snapshot.projects.count) running projects", systemImage: "folder").font(
            .system(size: 15, weight: .medium))
          Spacer()
          Text("\(store.snapshot.projects.flatMap(\.ports).count) listening ports").foregroundStyle(
            Color.muted
          ).font(.system(size: 12))
        }.padding(17)
      }
      if store.snapshot.projects.isEmpty {
        EmptyState(
          symbol: "folder", title: "No development projects running",
          detail:
            "Start a Node, Python, Bun, Go, or other local development server. Projects are grouped by their working directory."
        ).frame(height: 500)
      }
      ForEach(store.snapshot.projects) { project in
        HStack(spacing: 15) {
          Image(systemName: "folder").font(.system(size: 14)).foregroundStyle(
            MonitorTab.projects.color
          ).frame(width: 28, height: 28).background(
            MonitorTab.projects.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
          VStack(alignment: .leading, spacing: 5) {
            Text(project.name).font(.system(size: 16, weight: .semibold))
            Text("\(project.runtime) · \(project.processes.count) processes").font(
              .system(size: 12)
            ).foregroundStyle(Color.muted)
          }.help(project.id)
          Spacer()
          ForEach(project.ports, id: \.self) { port in
            Button {
              NSWorkspace.shared.open(URL(string: "http://localhost:\(port)")!)
            } label: {
              StatusPill(title: "\(port)", color: MonitorTab.projects.color)
            }.buttonStyle(.plain).help("Open localhost:\(port)")
          }
          if let since = project.idleSince, Date().timeIntervalSince(since) > 60 {
            StatusPill(
              title: "idle \(Format.duration(Date().timeIntervalSince(since)))", color: .gray,
              symbol: "moon")
          } else if project.cpu >= 0.5 {
            StatusPill(title: "working", color: MonitorTab.battery.color, symbol: "bolt")
          }
          Text(Format.memory(project.memory)).font(.system(size: 16, weight: .semibold)).frame(
            width: 90, alignment: .trailing)
          Button {
            pending = project.processes
            name = project.name
            confirm = true
          } label: {
            Image(systemName: "stop.circle").foregroundStyle(Color.muted)
          }.buttonStyle(.plain).help("Stop \(project.name)…")
        }.frame(height: 60).padding(.horizontal, 15).contextMenu {
          Button("Reveal Project in Finder") {
            NSWorkspace.shared.open(URL(fileURLWithPath: project.id))
          }
          Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(project.id, forType: .string)
          }
          Button("Stop…") {
            pending = project.processes
            name = project.name
            confirm = true
          }
        }
      }
      Spacer(minLength: 20)
      Text(
        "Idle means less than 0.5% of one CPU core while observed. Network requests and user activity are not inferred."
      ).font(.system(size: 10)).foregroundStyle(Color.muted).padding(12)
    }.padding(7).frame(minHeight: 640).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 23)
    )
    .alert("Stop \(name)?", isPresented: $confirm) {
      Button("Cancel", role: .cancel) {}
      Button("Stop", role: .destructive) { store.stop(pending) }
    } message: {
      Text(
        "\(pending.count) processes will receive a termination request. Unsaved work may be lost.")
    }
  }
}

struct AppDetailView: View {
  @ObservedObject var store: MonitorStore
  var app: AppStat
  @Environment(\.dismiss) private var dismiss
  @State private var quit = false
  @State private var force = false
  @State private var process: ProcessStat?
  var current: AppStat { store.snapshot.apps.first { $0.id == app.id } ?? app }
  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 15) {
        AppIcon(image: app.icon, size: 45)
        VStack(alignment: .leading, spacing: 4) {
          Text(app.name).font(.system(size: 24, weight: .semibold))
          Text("\(current.processes.count) processes · \(Format.memory(current.memory))").font(
            .system(size: 12)
          ).foregroundStyle(Color.muted)
        }
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      HStack(spacing: 14) {
        detail("CPU", Format.percent(store.normalizedCPU(current.cpu), precise: true))
        detail("Memory", Format.memory(current.memory))
        detail("Disk Writes", Format.rate(current.write))
        detail("GPU", current.gpu.map { Format.percent($0, precise: true) } ?? "—")
      }
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Recorded history").font(.system(size: 12, weight: .semibold))
          Spacer()
          Text("Last \(store.historyRange == .live ? "1 h" : store.historyRange.rawValue)").font(
            .system(size: 11)
          ).foregroundStyle(Color.muted)
        }
        HistoryChart(
          samples: store.displayedAppHistory,
          tab: store.selectedTab == .overview ? .memory : store.selectedTab,
          appPower: store.selectedTab == .battery
        ).frame(height: 115)
      }.padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 14))
      HStack {
        Text("Process")
        Spacer()
        Text("PID").frame(width: 65, alignment: .trailing)
        Text("CPU").frame(width: 70, alignment: .trailing)
        Text("Memory").frame(width: 100, alignment: .trailing)
        Spacer().frame(width: 24)
      }.font(.system(size: 11)).foregroundStyle(Color.muted)
      ScrollView {
        LazyVStack(spacing: 0) {
          ForEach(current.processes) { p in
            HStack {
              Text(p.name).font(.system(size: 12)).lineLimit(1).help(p.path)
              Spacer()
              Text("\(p.pid)").frame(width: 65, alignment: .trailing)
              Text(Format.percent(store.normalizedCPU(p.cpu), precise: true)).frame(width: 70, alignment: .trailing)
              Text(p.accessible ? Format.memory(p.memory) : "Restricted").frame(
                width: 100, alignment: .trailing)
              Button {
                process = p
                force = false
                quit = true
              } label: {
                Image(systemName: "xmark.circle")
              }.buttonStyle(.plain).foregroundStyle(Color.muted).help("Stop this process…")
            }.font(.system(size: 11)).monospacedDigit().padding(.vertical, 8)
          }
        }
      }.frame(minHeight: 170, maxHeight: 230)
      HStack {
        if let path = app.bundlePath {
          Button("Reveal in Finder") {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
          }
        }
        Spacer()
        Button("Quit…") {
          force = false
          process = nil
          quit = true
        }
        Button("Force Quit…") {
          force = true
          process = nil
          quit = true
        }.tint(.red)
      }
    }.padding(24).frame(width: 700).background(Color.window).preferredColorScheme(.dark)
      .alert("\(force ? "Force quit" : "Quit") \(process?.name ?? app.name)?", isPresented: $quit) {
        Button("Cancel", role: .cancel) {}
        Button(force ? "Force Quit" : "Quit", role: .destructive) {
          if let process {
            store.stop([process], force: force)
          } else {
            store.quitApp(current, force: force)
          }
          dismiss()
        }
      } message: {
        Text(
          "\(process == nil ? current.processes.count : 1) processes will close. Unsaved work may be lost."
        )
      }
  }
  private func detail(_ name: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(name).font(.system(size: 11)).foregroundStyle(Color.muted)
      Text(value).font(.system(size: 17, weight: .semibold))
    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 12))
  }
}
struct SettingsView: View {
  @ObservedObject var store: MonitorStore
  @Environment(\.dismiss) private var dismiss
  @State private var section = "General"
  @State private var login = SMAppService.mainApp.status == .enabled
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Text("Settings").font(.system(size: 23, weight: .semibold))
        Spacer()
        Button("Done") {
          store.saveLayout()
          dismiss()
        }.keyboardShortcut(.cancelAction)
      }
      Picker("Section", selection: $section) {
        ForEach(["General", "Layout", "Menu Bar", "Sensors"], id: \.self) { Text($0) }
      }.pickerStyle(.segmented)
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          if section == "General" {
            settingsRow("Refresh interval") {
              Picker("", selection: $store.interval) {
                Text("1 second").tag(1.0)
                Text("2 seconds").tag(2.0)
                Text("5 seconds").tag(5.0)
                Text("10 seconds").tag(10.0)
              }.labelsHidden().frame(width: 150)
            }
            Toggle("Show CPU use per core (apps can exceed 100%)", isOn: $store.perCoreCPU)
            Toggle("Show network speeds in bits per second", isOn: $store.networkBits)
            Toggle("Use Fahrenheit for temperatures", isOn: $store.fahrenheit)
            Toggle("Send notifications for unusual app activity", isOn: $store.notifications)
            Toggle("Open \(AppIdentity.name) at login", isOn: $login).onChange(of: login) { _, enabled in
              do {
                if enabled {
                  try SMAppService.mainApp.register()
                } else {
                  try SMAppService.mainApp.unregister()
                }
              } catch {
                store.message = error.localizedDescription
                login = SMAppService.mainApp.status == .enabled
              }
            }
            Divider()
            Text("History").font(.system(size: 15, weight: .semibold))
            Text(
              "30 days of system and app history are kept locally. One-minute averages are saved while monitoring is active. Traffic totals cover the periods observed by this app."
            ).font(.system(size: 12)).foregroundStyle(Color.muted)
            Button("Show History Folder") {
              let path = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(
                  "MacMonitor")
              NSWorkspace.shared.open(path)
            }
            Text("\(AppIdentity.name) · Version \(AppIdentity.version)\nSystem monitoring and cleanup for your Mac.").font(
              .system(size: 12)
            ).foregroundStyle(Color.muted).padding(.top, 12)
          } else if section == "Layout" {
            Text("Choose and reorder tabs").font(.system(size: 14, weight: .semibold))
            ForEach(Array(store.tabOrder.enumerated()), id: \.element.id) { index, tab in
              HStack {
                Toggle(
                  tab.rawValue,
                  isOn: Binding(
                    get: { !store.hiddenTabs.contains(tab) },
                    set: {
                      if $0 { store.hiddenTabs.remove(tab) } else { store.hiddenTabs.insert(tab) }
                      store.saveLayout()
                    })
                ).disabled(tab == .overview)
                Spacer()
                if [.cpu, .memory, .gpu, .disk, .network, .battery].contains(tab) {
                  Toggle(
                    "Overview card",
                    isOn: Binding(
                      get: { !store.hiddenCards.contains(tab) },
                      set: {
                        if $0 {
                          store.hiddenCards.remove(tab)
                        } else {
                          store.hiddenCards.insert(tab)
                        }
                        store.saveLayout()
                      })
                  ).font(.system(size: 11))
                }
                Button {
                  if index > 0 {
                    store.tabOrder.swapAt(index, index - 1)
                    store.saveLayout()
                  }
                } label: {
                  Image(systemName: "arrow.up")
                }.disabled(index == 0)
                Button {
                  if index < store.tabOrder.count - 1 {
                    store.tabOrder.swapAt(index, index + 1)
                    store.saveLayout()
                  }
                } label: {
                  Image(systemName: "arrow.down")
                }.disabled(index == store.tabOrder.count - 1)
              }
            }
            Button("Reset Layout") { store.resetLayout() }
          } else if section == "Menu Bar" {
            Text("Live readouts in the menu bar").font(.system(size: 14, weight: .semibold))
            Text(
              "Click the menu bar readout for a compact dashboard. Hold ⌘ to move it along your menu bar."
            ).font(.system(size: 12)).foregroundStyle(Color.muted)
            ForEach([MonitorTab.cpu, .memory, .gpu, .network, .disk, .battery]) { tab in
              Toggle(
                tab.rawValue,
                isOn: Binding(
                  get: { store.menuMetrics.contains(tab) },
                  set: {
                    if $0 { store.menuMetrics.insert(tab) } else { store.menuMetrics.remove(tab) }
                    store.saveLayout()
                  }))
            }
          } else {
            HStack(spacing: 14) {
              SmallStatCard(
                card: StatCardData(
                  title: "CPU Temperature", symbol: "thermometer.medium",
                  value: store.temperature(store.snapshot.cpuTemperature)),
                color: MonitorTab.projects.color)
              SmallStatCard(
                card: StatCardData(
                  title: "GPU Temperature", symbol: "thermometer.medium",
                  value: store.temperature(store.snapshot.gpuTemperature)),
                color: MonitorTab.gpu.color)
            }
            Text("Fan speeds").font(.system(size: 15, weight: .semibold))
            if store.snapshot.fans.isEmpty {
              Text("No accessible fans on this Mac. Fanless Macs have no fan readings.").font(
                .system(size: 12)
              ).foregroundStyle(Color.muted)
            }
            ForEach(Array(store.snapshot.fans.enumerated()), id: \.offset) { i, rpm in
              HStack {
                Label("Fan \(i+1)", systemImage: "fan")
                Spacer()
                Text(String(format: "%.0f rpm", rpm))
                StatusPill(title: "Automatic", color: MonitorTab.cpu.color)
              }
            }
            Text(
              "macOS manages fan speed. Manual fan control needs a privileged helper and is not included in this build."
            ).font(.system(size: 12)).foregroundStyle(Color.muted)
            Text(
              "Sensor availability depends on the Mac model. Unavailable readings appear as a dash."
            ).font(.system(size: 12)).foregroundStyle(Color.muted)
          }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
          Color.surface, in: RoundedRectangle(cornerRadius: 15))
      }.frame(height: 455)
    }.padding(24).frame(width: 660).background(Color.window).preferredColorScheme(.dark)
      .environmentObject(store)
  }
  private func settingsRow<C: View>(_ title: String, @ViewBuilder control: () -> C) -> some View {
    HStack {
      Text(title)
      Spacer()
      control()
    }
  }
}
struct AlertsView: View {
  @ObservedObject var store: MonitorStore
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(spacing: 16) {
      HStack {
        Text("Activity alerts").font(.system(size: 22, weight: .semibold))
        Spacer()
        Button("Clear") { store.alerts = [] }
        Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      if store.alerts.isEmpty {
        EmptyState(
          symbol: "checkmark.shield", title: "Everything looks good",
          detail:
            "Sustained high CPU, growing memory, heavy disk writes, and network traffic appear here."
        ).frame(height: 300)
      } else {
        ScrollView {
          VStack(spacing: 12) {
            ForEach(store.alerts) { alert in
              VStack(alignment: .leading, spacing: 6) {
                HStack {
                  Text(alert.title).font(.system(size: 14, weight: .semibold))
                  Spacer()
                  Text(alert.date, style: .time).font(.system(size: 10)).foregroundStyle(
                    Color.muted)
                }
                Text(alert.detail).font(.system(size: 12)).foregroundStyle(Color.muted)
              }.padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
            }
          }
        }.frame(height: 330)
      }
    }.padding(24).frame(width: 620).background(Color.window).preferredColorScheme(.dark)
  }
}
