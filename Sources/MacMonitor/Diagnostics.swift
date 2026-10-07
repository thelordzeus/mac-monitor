import Darwin
import Foundation
import SystemBridge

enum Diagnostics {
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
    history.append(sample, duration: 2)
    sample.date = sample.date.addingTimeInterval(2)
    sample.download = 2000
    sample.cpu = 60
    history.append(sample, duration: 2)
    history.flush()
    let rows = history.samples(since: Date().addingTimeInterval(-60))
    let totals = history.totals(since: Date().addingTimeInterval(-60))
    check(history.error == nil, "SQLite operations succeed: \(history.error ?? "")")
    check(rows.count == 1, "History aggregation produces one saved point")
    check(rows.first?.cpu == 50, "History preserves average CPU")
    check(
      totals.download == 6000 && totals.upload == 2000,
      "History integrates actual observed byte rates")
    if let app = sample.apps.first {
      check(
        !history.samples(since: Date().addingTimeInterval(-60), appID: app.id, tab: .memory)
          .isEmpty, "Per-app history persists")
    }
    try? FileManager.default.removeItem(at: folder)
    check(Format.bytes(1_500_000_000) == "1.50 GB", "Byte formatting")
    check(Format.rate(1_000_000, bits: true) == "8.0 Mbps", "Bits formatting")
    check(Format.duration(7380) == "2h 03m" || Format.duration(7380) == "2h 3m", "Time formatting")
    if failures.isEmpty {
      print(
        "PASS: controlled single-core CPU load, live metrics, process grouping, PID protection, SQLite history, per-app history, traffic integration, and formatting."
      )
    } else {
      for failure in failures { print("FAIL: \(failure)") }
      exit(1)
    }
  }
}
