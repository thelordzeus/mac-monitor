import Darwin
import Foundation
import SystemBridge

enum Diagnostics {
  static let transferSize = 8 * 1024 * 1024
  static func runIOWorker() {
    let listener = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard listener >= 0, bound == 0, listen(listener, 1) == 0 else { exit(1) }
    defer { close(listener) }
    var addressSize = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(listener, $0, &addressSize)
      }
    }
    let client = socket(AF_INET, SOCK_STREAM, 0)
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard client >= 0, connected == 0 else { exit(1) }
    defer { close(client) }
    let server = accept(listener, nil, nil)
    guard server >= 0 else { exit(1) }
    defer { close(server) }
    print("READY")
    fflush(stdout)
    guard readLine() != nil else { return }
    DispatchQueue.global().async {
      let data = Data(repeating: 0x35, count: 65536)
      data.withUnsafeBytes { bytes in
        var written = 0
        while written < transferSize {
          let count = send(client, bytes.baseAddress!, min(bytes.count, transferSize - written), 0)
          if count <= 0 { break }
          written += count
        }
      }
    }
    var buffer = [UInt8](repeating: 0, count: 65536)
    var received = 0
    while received < transferSize {
      let count = recv(server, &buffer, min(buffer.count, transferSize - received), 0)
      if count <= 0 { exit(1) }
      received += count
    }
    // A known, flushed write verifies process disk accounting separately from
    // whole-device rates. The file belongs exclusively to this test process.
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("MacMonitorIO-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: file) }
    do {
      try Data(repeating: 0x35, count: transferSize).write(to: file)
      let handle = try FileHandle(forWritingTo: file)
      _ = fsync(handle.fileDescriptor)
      try handle.close()
    } catch { exit(1) }
    print("TRANSFERRED")
    fflush(stdout)
    _ = readLine() // Keep both TCP endpoints alive for the next nettop sample.
  }
  static func runTests() {
    var failures: [String] = []
    func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
    let worker = Process()
    worker.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    worker.arguments = ["--cpu-worker"]
    worker.standardOutput = FileHandle.nullDevice
    worker.standardError = FileHandle.nullDevice
    do { try worker.run() } catch { failures.append("Start controlled CPU worker: \(error)") }
    defer { if worker.isRunning { worker.terminate() } }
    let memoryWorker = Process()
    memoryWorker.executableURL = worker.executableURL
    memoryWorker.arguments = ["--memory-worker"]
    let ready = Pipe()
    memoryWorker.standardOutput = ready
    memoryWorker.standardError = FileHandle.nullDevice
    do {
      try memoryWorker.run()
      _ = ready.fileHandleForReading.availableData
    } catch { failures.append("Start controlled memory worker: \(error)") }
    defer { if memoryWorker.isRunning { memoryWorker.terminate() } }
    let ioWorker = Process()
    ioWorker.executableURL = worker.executableURL
    ioWorker.arguments = ["--io-worker"]
    let ioInput = Pipe()
    let ioOutput = Pipe()
    ioWorker.standardInput = ioInput
    ioWorker.standardOutput = ioOutput
    ioWorker.standardError = FileHandle.nullDevice
    do {
      try ioWorker.run()
      _ = ioOutput.fileHandleForReading.availableData
    } catch { failures.append("Start controlled I/O worker: \(error)") }
    defer { if ioWorker.isRunning { ioWorker.terminate() } }
    let collector = Collector()
    let first = collector.collect()
    Thread.sleep(forTimeInterval: 1.1)
    let second = collector.collect()
    check(second.cpu >= 0 && second.cpu <= 100, "CPU percentage must be in range")
    check(second.totalMemory > 0, "Physical memory must be available")
    check(
      second.memoryUsed <= second.totalMemory && second.memoryUsed > 0,
      "Used memory must be bounded")
    check(second.processCount > 20, "Process enumeration must return live processes")
    let workerReading = second.apps.flatMap(\.processes).first {
      $0.pid == worker.processIdentifier
    }
    check(
      workerReading.map { $0.cpu > 30 && $0.cpu < 130 } == true,
      "A busy single-core process must read approximately 100% of a core (actual \(workerReading?.cpu ?? -1))"
    )
    check(
      second.apps.flatMap(\.processes).count == second.processCount,
      "Every PID must belong to exactly one group")
    check(
      Set(second.apps.flatMap(\.processes).map(\.pid)).count == second.processCount,
      "No process may be counted twice")
    check(
      second.diskFree <= second.diskTotal && second.diskTotal > 0, "Disk capacity must be valid")
    check(second.download >= 0 && second.upload >= 0, "Network rates cannot be negative")
    let memoryReading = second.apps.flatMap(\.processes).first { $0.pid == memoryWorker.processIdentifier }
    check(memoryReading.map { $0.memory >= 256 * 1024 * 1024 && $0.memory < 320 * 1024 * 1024 } == true,
      "A process touching 256 MiB must have a matching footprint (actual \(memoryReading?.memory ?? -1))")
    print("Measured CPU worker: \(Format.percent(workerReading?.cpu ?? 0, precise: true)) of one core; 256 MiB worker footprint: \(Format.memory(memoryReading?.memory ?? 0)).")
    ioInput.fileHandleForWriting.write(Data("transfer\n".utf8))
    _ = ioOutput.fileHandleForReading.availableData
    var written = 0.0
    var finalIO = second
    // nettop refreshes on the sixth collection, using its own longer window.
    for _ in 0..<4 {
      Thread.sleep(forTimeInterval: 0.5)
      finalIO = collector.collect()
      let process = finalIO.apps.flatMap(\.processes).first { $0.pid == ioWorker.processIdentifier }
      written += (process?.write ?? 0) * finalIO.observedDuration
    }
    let ioApp = finalIO.apps.first { $0.processes.contains { $0.pid == ioWorker.processIdentifier } }
    let networkDuration = finalIO.uptime - first.uptime
    let downloaded = (ioApp?.download ?? 0) * networkDuration
    let uploaded = (ioApp?.upload ?? 0) * networkDuration
    let expectedNetwork = Double(transferSize) // One send and one receive in this process.
    check(abs(downloaded - expectedNetwork) < 65536 && abs(uploaded - expectedNetwork) < 65536,
      "An 8 MiB local TCP transfer must account for sent and received payloads (in \(downloaded), out \(uploaded))")
    check(abs(written - Double(transferSize)) < 65536,
      "An 8 MiB flushed write must match the worker's disk counters (actual \(written))")
    print("Measured I/O worker: \(Int(downloaded)) received bytes, \(Int(uploaded)) sent bytes, \(Int(written)) disk bytes; expected \(Int(expectedNetwork))/\(Int(expectedNetwork))/\(transferSize).")
    ioInput.fileHandleForWriting.write(Data("quit\n".utf8))
    ioWorker.waitUntilExit()
    collector.resetBaselines()
    let reset = collector.collect()
    check(reset.observedDuration == 0 && reset.cpu == 0 && reset.download == 0 && reset.diskWrite == 0,
      "Pause/resume resets rate baselines without recording the unobserved interval")
    check(mm_signal(1, 0, SIGTERM) == EPERM, "Protect PID 1")
    check(mm_signal(getpid(), 0, SIGTERM) == EPERM, "Protect monitor process")
    check(mm_signal(99_999_999, 0, SIGTERM) == ESRCH, "Reject vanished processes")
    // Verify PID identity protection without terminating anything.
    check(mm_signal(getpid() + 1, 0, 0) != 0, "Reject stale process identities")
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
      "MacMonitorTests-\(UUID().uuidString)")
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch { failures.append("Create test directory") }
    let history = HistoryStore(url: folder.appendingPathComponent("history.sqlite"))
    var sample = first
    sample.date = Date()
    sample.download = 1000
    sample.upload = 500
    sample.diskWrite = 2000
    sample.cpu = 40
    sample.gpu = 20
    sample.apps = [AppStat(id: "test", name: "Test", processes: [ProcessStat(pid: 42, parent: 1, uid: 0, start: 1,
      name: "Test", path: "", cpu: 40, memory: 1000, read: 0, write: 1000, gpu: nil, power: nil, accessible: true)], icon: nil)]
    history.append(sample, duration: 1)
    sample.date = sample.date.addingTimeInterval(3)
    sample.download = 2000
    sample.cpu = 80
    sample.gpu = 60
    sample.apps[0].processes[0].cpu = 80
    sample.apps[0].processes[0].memory = 3000
    history.append(sample, duration: 3)
    let beforeFlush = history.totals(since: Date().addingTimeInterval(-60))
    check(beforeFlush.averageCPU == 70 && beforeFlush.observedDuration == 4,
      "Today's CPU average includes pending samples and weights by observed time")
    history.flush()
    let rows = history.samples(since: Date().addingTimeInterval(-60))
    let totals = history.totals(since: Date().addingTimeInterval(-60))
    check(history.error == nil, "SQLite operations succeed: \(history.error ?? "")")
    check(rows.count == 1, "History aggregation produces one saved point")
    check(rows.first?.cpu == 70 && rows.first?.gpu == 50, "History preserves weighted CPU/GPU averages")
    check(
      totals.download == 7000 && totals.upload == 2000 && totals.averageCPU == 70,
      "History integrates actual observed byte rates")
    if let app = sample.apps.first {
      check(history.samples(since: Date().addingTimeInterval(-60), appID: app.id, tab: .memory).first?.memory == 2500,
        "Per-app history weights unequal collection intervals")
      check(history.samples(since: Date().addingTimeInterval(-60), appID: app.id, tab: .gpu).isEmpty,
        "Unavailable GPU history must not become a fabricated zero")
      check(history.samples(since: Date().addingTimeInterval(-60), appID: app.id, tab: .battery).isEmpty,
        "Unavailable power history must not become a fabricated zero")
    }
    sample.date = sample.date.addingTimeInterval(2)
    sample.cpu = 10
    history.append(sample, duration: 2)
    check(history.totals(since: Date().addingTimeInterval(-60)).averageCPU == 50,
      "Today's average combines saved and pending samples")
    MainActor.assumeIsolated {
      let store = MonitorStore(start: false)
      var high = sample.apps[0]
      high.id = "high"
      high.name = "High"
      high.processes[0].cpu = 90
      var low = high
      low.id = "low"
      low.name = "Low"
      low.processes[0].cpu = 1
      store.snapshot.apps = [low, high]
      store.pinnedApps = [low.id]
      store.search = "Low"
      check(store.topApp(for: .cpu)?.id == high.id, "Top App ignores pins and search")
      store.snapshot.cores = 10
      store.selectedTab = .cpu
      store.appHistory = [Sample(timestamp: 1, cpu: 100, memory: 0, gpu: nil, diskRead: 0, diskWrite: 0, download: 0, upload: 0, battery: nil)]
      check(store.displayedAppHistory.first?.cpu == (store.perCoreCPU ? 100 : 10),
        "App history uses the same CPU scale as current readings")
    }
    try? FileManager.default.removeItem(at: folder)
    check(Format.bytes(1_500_000_000) == "1.50 GB", "Byte formatting")
    check(Format.rate(1_000_000, bits: true) == "8.0 Mbps", "Bits formatting")
    check(Format.duration(7380) == "2h 03m" || Format.duration(7380) == "2h 3m", "Time formatting")
    if failures.isEmpty {
      print(
        "PASS: controlled CPU and memory workloads, live metrics, process grouping, PID protection, pause baselines, weighted pending/saved history, unknown readings, Top App ranking, CPU scale, traffic integration, and formatting."
      )
    } else {
      for failure in failures { print("FAIL: \(failure)") }
      exit(1)
    }
  }
}
