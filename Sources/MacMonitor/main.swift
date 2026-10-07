import AppKit
import Foundation
import SwiftUI
import SystemBridge

if CommandLine.arguments.contains("--cpu-worker") {
  let deadline = ProcessInfo.processInfo.systemUptime + 8
  var value: UInt64 = 1
  while ProcessInfo.processInfo.systemUptime < deadline {
    for _ in 0..<100_000 { value = value &* 6_364_136_223_846_793_005 &+ 1 }
  }
  print(value)
} else if CommandLine.arguments.contains("--diagnostics") {
  let collector = Collector()
  _ = collector.collect()
  Thread.sleep(forTimeInterval: 1.2)
  let s = collector.collect()
  let result: [String: Any] = [
    "cpu": s.cpu, "memoryUsed": s.memoryUsed, "totalMemory": s.totalMemory,
    "diskTotal": s.diskTotal, "diskFree": s.diskFree, "diskRead": s.diskRead,
    "diskWrite": s.diskWrite, "download": s.download, "upload": s.upload, "gpu": s.gpu as Any,
    "gpuMemory": s.gpuMemory as Any, "cpuTemperature": s.cpuTemperature as Any,
    "gpuTemperature": s.gpuTemperature as Any, "fans": s.fans, "battery": s.battery.level,
    "batteryHealth": s.battery.health as Any, "batteryTemperature": s.battery.temperature as Any,
    "power": s.battery.watts as Any, "processes": s.processCount,
    "apps": s.apps.filter { !$0.isSystem }.prefix(12).map {
      [
        "name": $0.name, "processes": $0.processes.count, "cpu": $0.cpu, "memory": $0.memory,
        "gpu": $0.gpu as Any, "power": $0.power as Any,
      ]
    }, "projects": s.projects.map { ["name": $0.name, "ports": $0.ports, "memory": $0.memory] },
    "networkPerApp": s.networkAvailable,
  ]
  if let data = try? JSONSerialization.data(
    withJSONObject: result, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
    let str = String(data: data, encoding: .utf8)
  {
    print(str)
  } else {
    print(
      "CPU \(s.cpu), memory \(s.memoryUsed), \(s.processCount) processes, \(s.apps.count) groups, GPU \(String(describing:s.gpu))"
    )
  }
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
      store.liveSamples.append(s.sample)
      Thread.sleep(forTimeInterval: 0.25)
    }
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
    print("Rendered real-metric dashboards to \(folder.path)")
  }
} else {
  MacMonitorApp.main()
}
