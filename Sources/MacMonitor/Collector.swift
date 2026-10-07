import AppKit
import Darwin
import Foundation
import IOKit
import IOKit.ps
import Metal
import SystemBridge
import SystemConfiguration

func tupleString<T>(_ value: T) -> String {
  var copy = value
  return withUnsafePointer(to: &copy) {
    $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
  }
}
func runCommand(_ executable: String, _ arguments: [String], timeout: Double = 6) -> String {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: executable)
  process.arguments = arguments
  let pipe = Pipe()
  process.standardOutput = pipe
  process.standardError = FileHandle.nullDevice
  do { try process.run() } catch { return "" }
  let timeoutWork = DispatchWorkItem { if process.isRunning { process.terminate() } }
  DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)
  let data = pipe.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  timeoutWork.cancel()
  return String(data: data, encoding: .utf8) ?? ""
}
func registryProperties(_ object: io_registry_entry_t) -> [String: Any] {
  var properties: Unmanaged<CFMutableDictionary>?
  guard
    IORegistryEntryCreateCFProperties(object, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS
  else { return [:] }
  return properties?.takeRetainedValue() as? [String: Any] ?? [:]
}
func sysInt(_ name: String) -> Int {
  var value: Int32 = 0
  var size = MemoryLayout<Int32>.size
  return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
}

final class Collector {
  private var previousSystem: MMSystem?
  private var previousProcesses: [Int32: MMProcess] = [:]
  private var previousGPU: [Int32: Double] = [:]
  private var previousTime = ProcessInfo.processInfo.systemUptime
  private var networkCounters: [Int32: (Double, Double)] = [:]
  private var networkRates: [Int32: (Double, Double)] = [:]
  private var networkTime: Double?
  private var ports: [Int32: [Int]] = [:]
  private var cwdCache: [String: String] = [:]
  private var idleTimes: [String: Date] = [:]
  private var iteration = 0
  private var buffer = [MMProcess](repeating: MMProcess(), count: 8192)
  private var iconCache: [String: NSImage] = [:]
  private var networkOK = false
  private var volumes: [String] = []
  private var interfaceName = "en0"
  private var interfaceType = "Network"
  private let gpuName = MTLCreateSystemDefaultDevice()?.name ?? "GPU"

  func resetBaselines() {
    previousSystem = nil
    previousProcesses.removeAll()
    previousGPU.removeAll()
    networkCounters.removeAll()
    networkRates.removeAll()
    networkTime = nil
    idleTimes.removeAll()
    iteration = 0
  }
  func collect(maxInterval: Double? = nil) -> Snapshot {
    let now = ProcessInfo.processInfo.systemUptime
    let dt = max(0.1, now - previousTime)
    if let maxInterval, dt > maxInterval { resetBaselines() }
    let raw = mm_system()
    var s = Snapshot()
    s.date = Date()
    s.uptime = now
    s.gpuName = gpuName
    s.cores = ProcessInfo.processInfo.processorCount
    s.performanceCores = sysInt("hw.perflevel0.logicalcpu")
    s.efficiencyCores = sysInt("hw.perflevel1.logicalcpu")
    if let old = previousSystem {
      s.observedDuration = dt
      let user = delta(raw.user, old.user) + delta(raw.nice, old.nice)
      let system = delta(raw.system, old.system)
      let idle = delta(raw.idle, old.idle)
      let total = max(1, user + system + idle)
      s.user = 100 * user / total
      s.system = 100 * system / total
      s.cpu = s.user + s.system
      s.download = delta(raw.net_in, old.net_in) / dt
      s.upload = delta(raw.net_out, old.net_out) / dt
      s.diskRead = delta(raw.disk_read, old.disk_read) / dt
      s.diskWrite = delta(raw.disk_write, old.disk_write) / dt
    }
    s.load = raw.load
    s.totalMemory = Double(raw.total_memory)
    s.appMemory = Double(raw.app_memory)
    s.wired = Double(raw.wired)
    s.compressed = Double(raw.compressed)
    s.cached = Double(raw.cached)
    s.free = Double(raw.free_memory)
    s.swap = Double(raw.swap)
    s.pressure = raw.pressure >= 4 ? "Critical" : raw.pressure >= 2 ? "Elevated" : "Normal"
    if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: "/System/Volumes/Data")
    {
      s.diskTotal = (attrs[.systemSize] as? NSNumber)?.doubleValue ?? 0
      s.diskFree = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
    }
    if iteration % 5 == 0 {
      collectNetwork(now)
      collectPorts()
      volumes =
        (FileManager.default.mountedVolumeURLs(
          includingResourceValuesForKeys: [.volumeIsBrowsableKey, .volumeNameKey],
          options: [.skipHiddenVolumes]) ?? []).compactMap {
          guard let v = try? $0.resourceValues(forKeys: [.volumeIsBrowsableKey, .volumeNameKey]),
            v.volumeIsBrowsable == true
          else { return nil }
          return v.volumeName
        }
      let route = runCommand("/sbin/route", ["-n", "get", "default"], timeout: 2)
      if let line = route.components(separatedBy: .newlines).first(where: {
        $0.contains("interface:")
      }) {
        interfaceName = line.components(separatedBy: ":").last!.trimmingCharacters(in: .whitespaces)
      }
      if let interfaces = SCNetworkInterfaceCopyAll() as? [SCNetworkInterface],
        let current = interfaces.first(where: {
          (SCNetworkInterfaceGetBSDName($0) as String?) == interfaceName
        })
      {
        let type = SCNetworkInterfaceGetInterfaceType(current) as String?
        interfaceType =
          type == (kSCNetworkInterfaceTypeIEEE80211 as String)
          ? "Wi-Fi"
          : type == (kSCNetworkInterfaceTypeEthernet as String) ? "Ethernet" : type ?? "Network"
      }
    }
    s.networkAvailable = networkOK
    s.interface = interfaceName
    s.interfaceType = interfaceType
    s.volumes = volumes
    let gpu = gpuStats()
    s.gpu = gpu.0
    s.gpuMemory = gpu.1
    let gpuCounters = gpu.2
    let count = mm_processes(&buffer, Int32(buffer.count))
    s.processCount = Int(count)
    var rawByPID: [Int32: MMProcess] = [:]
    var statsByPID: [Int32: ProcessStat] = [:]
    for p in buffer.prefix(Int(count)) {
      rawByPID[p.pid] = p
      let old = previousProcesses[p.pid]
      let same = old?.start == p.start
      let cpu = same ? delta(p.cpu_ns, old!.cpu_ns) / (dt * 1_000_000_000) * 100 : 0
      let gpuTime = gpuCounters[p.pid]
      let oldGPU = previousGPU[p.pid]
      let gpuValue: Double? =
        same && gpuTime != nil && oldGPU != nil
        ? max(0, gpuTime! - oldGPU!) / (dt * 1_000_000_000) * 100 : nil
      let power: Double? =
        p.energy_available && same ? delta(p.energy_nj, old!.energy_nj) / (dt * 1_000_000_000) : nil
      statsByPID[p.pid] = ProcessStat(
        pid: p.pid, parent: p.ppid, uid: Int(p.uid), start: p.start, name: tupleString(p.name),
        path: tupleString(p.path), cpu: cpu, memory: Double(p.memory),
        read: same ? delta(p.read_bytes, old!.read_bytes) / dt : 0,
        write: same ? delta(p.write_bytes, old!.write_bytes) / dt : 0, gpu: gpuValue, power: power,
        accessible: p.accessible)
    }
    let running = NSWorkspace.shared.runningApplications
    var rootPaths: [Int32: String] = [:]
    var names: [String: String] = [:]
    for app in running {
      if let path = app.bundleURL?.path {
        let root = outerBundle(path) ?? path
        rootPaths[app.processIdentifier] = root
        if path == root { names[root] = app.localizedName }
      }
    }
    var groupMap: [String: [ProcessStat]] = [:]
    var bundlePaths: [String: String] = [:]
    for p in statsByPID.values {
      var bundle = outerBundle(p.path) ?? rootPaths[p.pid]
      var parent = p.parent
      var visited = Set<Int32>()
      while bundle == nil && parent > 1 && !visited.contains(parent) {
        visited.insert(parent)
        bundle = rootPaths[parent] ?? statsByPID[parent].flatMap { outerBundle($0.path) }
        parent = statsByPID[parent]?.parent ?? 0
      }
      if bundle == nil && p.path.contains("WebKit")
        && p.name.localizedCaseInsensitiveContains("Safari")
      {
        bundle = "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"
      }
      let key = bundle ?? "process:\(p.name)"
      if let bundle { bundlePaths[key] = bundle }
      groupMap[key, default: []].append(p)
    }
    s.apps = groupMap.map { key, processes in
      let path = bundlePaths[key]
      let name =
        path.map { names[$0] ?? URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
        ?? processes.first!.name
      if let path, iconCache[path] == nil {
        iconCache[path] = NSWorkspace.shared.icon(forFile: path)
      }
      var app = AppStat(
        id: key, name: name, bundlePath: path, processes: processes.sorted { $0.cpu > $1.cpu },
        icon: path.flatMap { iconCache[$0] }, isSystem: path == nil)
      for p in processes {
        app.download += networkRates[p.pid]?.0 ?? 0
        app.upload += networkRates[p.pid]?.1 ?? 0
      }
      return app
    }.sorted { $0.memory > $1.memory }
    s.projects = projects(statsByPID)
    s.battery = batteryStats()
    s.cpuTemperature = temperature(["Tp09", "Tp0T", "Tp01", "TC0P", "TC0E", "TC0F", "Tp0P"])
    s.gpuTemperature = temperature(["Tg0f", "Tg0P", "TG0P", "TG0D"])
    let fanCount = mm_smc_read("FNum")
    if fanCount.isFinite {
      s.fans = (0..<min(8, Int(fanCount))).compactMap {
        let v = mm_smc_read("F\($0)Ac")
        return v.isFinite ? v : nil
      }
    }
    previousSystem = raw
    previousProcesses = rawByPID
    previousGPU = gpuCounters
    previousTime = now
    iteration += 1
    return s
  }
  private func delta(_ a: UInt64, _ b: UInt64) -> Double { a >= b ? Double(a - b) : 0 }
  private func outerBundle(_ path: String) -> String? {
    let components = path.split(separator: "/")
    guard let index = components.firstIndex(where: { $0.lowercased().hasSuffix(".app") }) else {
      return nil
    }
    return "/" + components[...index].joined(separator: "/")
  }
  private func temperature(_ keys: [String]) -> Double? {
    let values = keys.map { mm_smc_read($0) }.filter { $0.isFinite && $0 > 0 && $0 < 150 }
    return values.max()
  }
  private func collectNetwork(_ now: Double) {
    let output = runCommand(
      "/usr/bin/nettop", ["-P", "-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out"], timeout: 3)
    var counters: [Int32: (Double, Double)] = [:]
    for line in output.components(separatedBy: .newlines) {
      let fields = line.components(separatedBy: ",")
      guard fields.count >= 3, let dot = fields[0].lastIndex(of: "."),
        let pid = Int32(fields[0][fields[0].index(after: dot)...]), let input = Double(fields[1]),
        let out = Double(fields[2])
      else { continue }
      counters[pid] = (input, out)
    }
    networkOK = !counters.isEmpty
    var rates: [Int32: (Double, Double)] = [:]
    if let previousTime = networkTime {
      let interval = max(0.1, now - previousTime)
      for (pid, count) in counters {
        if let previous = networkCounters[pid] {
          rates[pid] = (
            max(0, count.0 - previous.0) / interval, max(0, count.1 - previous.1) / interval
          )
        }
      }
    }
    networkCounters = counters
    networkRates = rates
    networkTime = now
  }
  private func collectPorts() {
    let text = runCommand("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"], timeout: 3)
    var map: [Int32: Set<Int>] = [:]
    var pid: Int32 = 0
    for line in text.components(separatedBy: .newlines) {
      if line.hasPrefix("p") { pid = Int32(line.dropFirst()) ?? 0 }
      if line.hasPrefix("n"), let part = line.split(separator: ":").last, let port = Int(part),
        pid > 0
      {
        map[pid, default: []].insert(port)
      }
    }
    ports = map.mapValues { $0.sorted() }
  }
  private func projects(_ stats: [Int32: ProcessStat]) -> [ProjectStat] {
    let runtimes = [
      "node", "bun", "deno", "python", "ruby", "php", "go", "java", "dotnet", "uvicorn", "cargo",
    ]
    var groups: [String: [ProcessStat]] = [:]
    for p in stats.values
    where p.uid == Int(getuid())
      && (runtimes.contains(where: { p.name.lowercased().hasPrefix($0) }) || ports[p.pid] != nil)
      && !p.path.contains(".app/")
    {
      let cacheKey = "\(p.pid):\(p.start)"
      var cwd = cwdCache[cacheKey]
      if cwd == nil || iteration % 15 == 0 {
        var path = [CChar](repeating: 0, count: 4096)
        if mm_cwd(p.pid, &path, Int32(path.count)) == 0 {
          cwd = String(cString: path)
          cwdCache[cacheKey] = cwd
        }
      }
      guard let cwd, cwd != "/", !cwd.hasPrefix("/System"), !cwd.hasPrefix("/usr"),
        cwd != NSHomeDirectory()
      else { continue }
      groups[cwd, default: []].append(p)
    }
    if cwdCache.count > 2000 {
      cwdCache = cwdCache.filter { key, _ in
        stats.values.contains { key == "\($0.pid):\($0.start)" }
      }
    }
    idleTimes = idleTimes.filter { groups[$0.key] != nil }
    return groups.map { path, processes in
      let cpu = processes.reduce(0) { $0 + $1.cpu }
      if cpu < 0.5 {
        if idleTimes[path] == nil { idleTimes[path] = Date() }
      } else {
        idleTimes[path] = nil
      }
      return ProjectStat(
        id: path, name: URL(fileURLWithPath: path).lastPathComponent,
        runtime: Array(Set(processes.map(\.name))).sorted().joined(separator: ", "),
        processes: processes, ports: Array(Set(processes.flatMap { ports[$0.pid] ?? [] })).sorted(),
        idleSince: idleTimes[path])
    }.sorted { $0.memory > $1.memory }
  }
  private func gpuStats() -> (Double?, Double?, [Int32: Double]) {
    var iterator: io_iterator_t = 0
    guard
      IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
    else { return (nil, nil, [:]) }
    defer { IOObjectRelease(iterator) }
    var utilization: Double?
    var memory: Double?
    var gpuTimes: [Int32: Double] = [:]
    while case let object = IOIteratorNext(iterator), object != 0 {
      let props = registryProperties(object)
      if let stats = props["PerformanceStatistics"] as? [String: Any] {
        utilization =
          (stats["Device Utilization %"] as? NSNumber)?.doubleValue
          ?? (stats["GPU Activity(%)"] as? NSNumber)?.doubleValue
        memory = (stats["In use system memory"] as? NSNumber)?.doubleValue
      }
      var children: io_iterator_t = 0
      if IORegistryEntryCreateIterator(
        object, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &children)
        == KERN_SUCCESS
      {
        while case let child = IOIteratorNext(children), child != 0 {
          let properties = registryProperties(child)
          if let creator = properties["IOUserClientCreator"] as? String,
            let pidString = creator.split(separator: ",").first?.split(separator: " ").last,
            let pid = Int32(pidString), let usage = properties["AppUsage"] as? [[String: Any]]
          {
            gpuTimes[pid, default: 0] += usage.reduce(0) {
              $0 + (($1["accumulatedGPUTime"] as? NSNumber)?.doubleValue ?? 0)
            }
          }
          IOObjectRelease(child)
        }
        IOObjectRelease(children)
      }
      IOObjectRelease(object)
    }
    return (utilization, memory, gpuTimes)
  }
  private func batteryStats() -> BatteryStat {
    var b = BatteryStat()
    if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
    {
      for source in sources {
        guard
          let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
            as? [String: Any], d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        else { continue }
        b.present = true
        let current = (d[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue ?? 0
        let maximum = (d[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue ?? 100
        b.level = current / max(1, maximum) * 100
        b.charging = d[kIOPSIsChargingKey] as? Bool ?? false
        b.plugged = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        let minutes =
          (d[b.charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? NSNumber)?.doubleValue
          ?? -1
        if minutes > 0 { b.remaining = minutes * 60 }
      }
    }
    let service = IOServiceGetMatchingService(
      kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    if service != 0 {
      let p = registryProperties(service)
      IOObjectRelease(service)
      b.cycles = (p["CycleCount"] as? NSNumber)?.intValue
      let maximum =
        (p["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
        ?? (p["MaxCapacity"] as? NSNumber)?.doubleValue
      if let maximum, let design = (p["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0 {
        b.health = min(100, maximum / design * 100)
      }
      if let t = (p["Temperature"] as? NSNumber)?.doubleValue { b.temperature = t / 100 }
      if let voltage = (p["Voltage"] as? NSNumber)?.doubleValue,
        let current = (p["InstantAmperage"] as? NSNumber)?.int64Value
      {
        let amperage = Double(Int16(truncatingIfNeeded: current))
        b.watts = abs(voltage * amperage) / 1_000_000
      }
    }
    return b
  }
}
