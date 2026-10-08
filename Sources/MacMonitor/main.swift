import AppKit
import Foundation
import SwiftUI
import SystemBridge

if CommandLine.arguments.contains("--io-worker") {
  Diagnostics.runIOWorker()
} else if CommandLine.arguments.contains("--memory-worker") {
  let size = 256 * 1024 * 1024
  let memory = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16384)
  for offset in stride(from: 0, to: size, by: 16384) {
    memory.storeBytes(of: UInt64(offset), toByteOffset: offset, as: UInt64.self)
  }
  print("READY")
  fflush(stdout)
  Thread.sleep(forTimeInterval: 15)
  memory.deallocate()
} else if CommandLine.arguments.contains("--cpu-worker") {
  let deadline = ProcessInfo.processInfo.systemUptime + 8
  var value: UInt64 = 1
  while ProcessInfo.processInfo.systemUptime < deadline {
    for _ in 0..<100_000 { value = value &* 6_364_136_223_846_793_005 &+ 1 }
  }
  print(value)
} else if CommandLine.arguments.contains("--diagnostics") {
  let collector = Collector()
  func option(_ name: String, fallback: Double) -> Double {
    guard let index = CommandLine.arguments.firstIndex(of: name),
      index + 1 < CommandLine.arguments.count,
      let value = Double(CommandLine.arguments[index + 1]), value.isFinite else { return fallback }
    return value
  }
  let count = Int(min(300, max(2, option("--samples", fallback: 2))))
  let interval = min(60, max(0.1, option("--sample-interval", fallback: 1.2)))
  let stream = CommandLine.arguments.contains("--stream")
  func emit(_ s: Snapshot) {
    let result: [String: Any] = [
      "timestamp": s.date.timeIntervalSince1970, "observedDuration": s.observedDuration,
      "cpuUser": s.user, "cpuSystem": s.system, "load": s.load,
      "cores": s.cores, "performanceCores": s.performanceCores, "efficiencyCores": s.efficiencyCores,
      "cpu": s.cpu, "memoryUsed": s.memoryUsed, "totalMemory": s.totalMemory,
      "memoryApp": s.appMemory, "memoryWired": s.wired, "memoryCompressed": s.compressed,
      "memoryCached": s.cached, "memoryFree": s.free, "memoryReserved": s.reservedMemory,
      "memoryAvailable": s.availableMemory, "swap": s.swap, "pressure": s.pressure,
      "diskTotal": s.diskTotal, "diskFree": s.diskFree, "diskRead": s.diskRead,
      "diskWrite": s.diskWrite, "download": s.download, "upload": s.upload, "gpu": s.gpu as Any,
      "gpuMemory": s.gpuMemory as Any, "cpuTemperature": s.cpuTemperature as Any,
      "gpuTemperature": s.gpuTemperature as Any, "fans": s.fans, "battery": s.battery.level,
      "batteryPresent": s.battery.present, "interface": s.interface, "interfaceType": s.interfaceType,
      "batteryHealth": s.battery.health as Any, "batteryTemperature": s.battery.temperature as Any,
      "power": s.battery.watts as Any, "processes": s.processCount,
      "apps": s.apps.filter { !$0.isSystem }.prefix(12).map {
        [
          "name": $0.name, "processes": $0.processes.count, "cpu": $0.cpu, "memory": $0.memory,
          "gpu": $0.gpu as Any, "power": $0.power as Any,
          "download": $0.download, "upload": $0.upload,
        ]
      }, "projects": s.projects.map { ["name": $0.name, "ports": $0.ports, "memory": $0.memory] },
      "networkPerApp": s.networkAvailable,
      "processReadings": s.apps.flatMap(\.processes).map {
        ["pid": $0.pid, "name": $0.name, "cpu": $0.cpu, "memory": $0.memory,
         "read": $0.read, "write": $0.write, "accessible": $0.accessible] as [String: Any]
      },
    ]
    if let data = try? JSONSerialization.data(
      withJSONObject: result, options: stream ? [.sortedKeys] : [.prettyPrinted, .sortedKeys]),
      let str = String(data: data, encoding: .utf8)
    {
      print(str)
      fflush(stdout)
    } else {
      print(
        "CPU \(s.cpu), memory \(s.memoryUsed), \(s.processCount) processes, \(s.apps.count) groups, GPU \(String(describing:s.gpu))"
      )
    }
  }
  var s = collector.collect()
  if stream { emit(s) }
  for _ in 1..<count {
    Thread.sleep(forTimeInterval: interval)
    s = collector.collect()
    if stream { emit(s) }
  }
  if !stream { emit(s) }
} else if CommandLine.arguments.contains("--self-test") {
  Diagnostics.runTests()
} else if let index = CommandLine.arguments.firstIndex(of: "--render"),
  CommandLine.arguments.count > index + 1
{
  try MainActor.assumeIsolated {
    let folder = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    _ = NSApplication.shared
    let store = MonitorStore(start: false)
    let collector = Collector()
    for _ in 0..<50 {
      let s = collector.collect()
      store.snapshot = s
      if s.observedDuration > 0 { store.liveSamples.append(s.sample) }
      Thread.sleep(forTimeInterval: 0.25)
    }
    let recordedHistory = HistoryStore()
    let capturedDate = store.snapshot.date
    store.today = recordedHistory.totals(since: Calendar.current.startOfDay(for: capturedDate))
    store.week = recordedHistory.totals(since: capturedDate.addingTimeInterval(-604800))
    store.month = recordedHistory.totals(since: capturedDate.addingTimeInterval(-2_592_000))
    store.audio.refresh(apps: store.snapshot.apps, force: true)
    for tab in MonitorTab.allCases {
      store.selectedTab = tab
      let view = DashboardView(store: store, exporting: true).environmentObject(store).frame(
        width: 1260, height: 890)
      let renderer = ImageRenderer(content: view)
      renderer.scale = 1.5
      renderer.colorMode = .nonLinear
      if let cgImage = DashboardImage.render(renderer),
        let png = DashboardImage.png(cgImage)
      {
        try png.write(to: folder.appendingPathComponent(tab.rawValue.lowercased() + ".png"))
      }
    }
    let floating = ImageRenderer(content: FloatingDashboard(store: store, open: {}).foregroundStyle(.white).frame(width: 340, height: 230))
    floating.scale = 2
    if let cgImage = DashboardImage.render(floating), let png = DashboardImage.png(cgImage) {
      try png.write(to: folder.appendingPathComponent("floating-dashboard.png"))
    }
    print("Rendered real-metric dashboards to \(folder.path)")
  }
} else {
  MacMonitorApp.main()
}
