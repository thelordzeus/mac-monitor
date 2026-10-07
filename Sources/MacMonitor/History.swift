import Darwin
import Foundation
import SQLite3

struct Totals {
  var download = 0.0
  var upload = 0.0
  var written = 0.0
  var averageCPU = 0.0
}
final class HistoryStore {
  private var db: OpaquePointer?
  private var pending: [(Snapshot, Double)] = []
  private var lastSaved = Date.distantPast
  private var lastRetention = Date.distantPast
  private(set) var error: String?
  let url: URL
  init(url: URL? = nil) {
    let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MacMonitor", isDirectory: true)
    self.url = url ?? folder.appendingPathComponent("history.sqlite")
    do {
      try FileManager.default.createDirectory(
        at: self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
    } catch { self.error = error.localizedDescription }
    guard sqlite3_open(self.url.path, &db) == SQLITE_OK else {
      error = "History database could not be opened."
      return
    }
    sqlite3_busy_timeout(db, 3000)
    execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;")
    execute(
      "CREATE TABLE IF NOT EXISTS samples (time REAL PRIMARY KEY, duration REAL, cpu REAL, memory REAL, gpu REAL, diskRead REAL, diskWrite REAL, download REAL, upload REAL, battery REAL);"
    )
    execute(
      "CREATE TABLE IF NOT EXISTS apps (time REAL, id TEXT, name TEXT, cpu REAL, memory REAL, gpu REAL, diskWrite REAL, download REAL, power REAL, PRIMARY KEY(time,id)); CREATE INDEX IF NOT EXISTS apps_id_time ON apps(id,time);"
    )
    var versionStatement: OpaquePointer?
    var version: Int32 = 0
    if sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &versionStatement, nil) == SQLITE_OK,
      sqlite3_step(versionStatement) == SQLITE_ROW
    {
      version = sqlite3_column_int(versionStatement, 0)
    }
    sqlite3_finalize(versionStatement)
    if version == 0 {
      // Repair app CPU points made by the initial development build before
      // Mach CPU ticks were converted to nanoseconds on Apple Silicon.
      var timebase = mach_timebase_info_data_t()
      mach_timebase_info(&timebase)
      let factor = Double(timebase.numer) / Double(timebase.denom)
      execute("UPDATE apps SET cpu=cpu*\(factor); PRAGMA user_version=1;")
    }
  }
  deinit { sqlite3_close(db) }
  private func execute(_ sql: String) {
    if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
      error = String(cString: sqlite3_errmsg(db))
    }
  }
  func append(_ s: Snapshot, duration: Double) {
    pending.append((s, duration))
    if lastSaved == .distantPast { lastSaved = s.date }
    if s.date.timeIntervalSince(lastSaved) >= 60 { flush() }
  }
  func flush() {
    guard !pending.isEmpty, db != nil else { return }
    let time = pending.last!.0.date.timeIntervalSince1970
    let duration = pending.reduce(0) { $0 + $1.1 }
    let n = Double(pending.count)
    func average(_ key: KeyPath<Snapshot, Double>) -> Double {
      pending.reduce(0) { $0 + $1.0[keyPath: key] * $1.1 } / max(duration, 0.01)
    }
    let gpu = pending.compactMap { $0.0.gpu }
    let battery = pending.filter { $0.0.battery.present }.map { $0.0.battery.level }
    var statement: OpaquePointer?
    execute("BEGIN TRANSACTION")
    if sqlite3_prepare_v2(
      db, "INSERT OR REPLACE INTO samples VALUES (?,?,?,?,?,?,?,?,?,?)", -1, &statement, nil)
      == SQLITE_OK
    {
      let values: [Double?] = [
        time, duration, average(\.cpu), average(\.memoryUsed),
        gpu.isEmpty ? nil : gpu.reduce(0, +) / Double(gpu.count), average(\.diskRead),
        average(\.diskWrite), average(\.download), average(\.upload),
        battery.isEmpty ? nil : battery.reduce(0, +) / Double(battery.count),
      ]
      for (i, v) in values.enumerated() {
        if let v {
          sqlite3_bind_double(statement, Int32(i + 1), v)
        } else {
          sqlite3_bind_null(statement, Int32(i + 1))
        }
      }
      if sqlite3_step(statement) != SQLITE_DONE { error = String(cString: sqlite3_errmsg(db)) }
    }
    sqlite3_finalize(statement)
    statement = nil
    var averages: [String: (String, [Double])] = [:]
    for (s, _) in pending {
      for a in s.apps {
        var row = averages[a.id] ?? (a.name, Array(repeating: 0, count: 6))
        let v = [a.cpu, a.memory, a.gpu ?? 0, a.write, a.download, a.power ?? 0]
        for i in 0..<6 { row.1[i] += v[i] / n }
        averages[a.id] = row
      }
    }
    if sqlite3_prepare_v2(
      db, "INSERT OR REPLACE INTO apps VALUES (?,?,?,?,?,?,?,?,?)", -1, &statement, nil)
      == SQLITE_OK
    {
      let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
      for (id, row) in averages {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        sqlite3_bind_double(statement, 1, time)
        sqlite3_bind_text(statement, 2, id, -1, transient)
        sqlite3_bind_text(statement, 3, row.0, -1, transient)
        for i in 0..<6 { sqlite3_bind_double(statement, Int32(i + 4), row.1[i]) }
        if sqlite3_step(statement) != SQLITE_DONE { error = String(cString: sqlite3_errmsg(db)) }
      }
    }
    sqlite3_finalize(statement)
    execute("COMMIT")
    pending.removeAll(keepingCapacity: true)
    lastSaved = Date(timeIntervalSince1970: time)
    if lastSaved.timeIntervalSince(lastRetention) > 3600 {
      let cutoff = time - 30 * 86400
      execute(
        "DELETE FROM samples WHERE time < \(cutoff); DELETE FROM apps WHERE time < \(cutoff);")
      lastRetention = lastSaved
    }
  }
  func samples(since: Date, appID: String? = nil, tab: MonitorTab = .cpu) -> [Sample] {
    var statement: OpaquePointer?
    let column: String
    switch tab {
    case .memory: column = "memory"
    case .gpu: column = "gpu"
    case .disk: column = "diskWrite"
    case .network: column = "download"
    case .battery: column = "power"
    default: column = "cpu"
    }
    let sql =
      appID == nil
      ? "SELECT time,cpu,memory,gpu,diskRead,diskWrite,download,upload,battery FROM samples WHERE time >= ? ORDER BY time"
      : "SELECT time,\(column) FROM apps WHERE time >= ? AND id=? ORDER BY time"
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_double(statement, 1, since.timeIntervalSince1970)
    if let appID {
      sqlite3_bind_text(
        statement, 2, appID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    }
    var result: [Sample] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      func d(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
      if appID != nil {
        var s = Sample(
          timestamp: d(0), cpu: 0, memory: 0, gpu: nil, diskRead: 0, diskWrite: 0, download: 0,
          upload: 0, battery: nil)
        switch tab {
        case .memory: s.memory = d(1)
        case .gpu: s.gpu = d(1)
        case .disk: s.diskWrite = d(1)
        case .network: s.download = d(1)
        case .battery: s.battery = d(1)
        default: s.cpu = d(1)
        }
        result.append(s)
      } else {
        result.append(
          Sample(
            timestamp: d(0), cpu: d(1), memory: d(2),
            gpu: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : d(3), diskRead: d(4),
            diskWrite: d(5), download: d(6), upload: d(7),
            battery: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : d(8)))
      }
    }
    if result.count > 600 {
      let stride = max(1, result.count / 600)
      return result.enumerated().filter { $0.offset % stride == 0 }.map(\.element)
    }
    return result
  }
  func totals(since: Date) -> Totals {
    var t = Totals()
    var stmt: OpaquePointer?
    if sqlite3_prepare_v2(
      db,
      "SELECT SUM(download*duration),SUM(upload*duration),SUM(diskWrite*duration),SUM(cpu*duration)/SUM(duration) FROM samples WHERE time>=?",
      -1, &stmt, nil) == SQLITE_OK
    {
      sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
      if sqlite3_step(stmt) == SQLITE_ROW {
        t = Totals(
          download: sqlite3_column_double(stmt, 0), upload: sqlite3_column_double(stmt, 1),
          written: sqlite3_column_double(stmt, 2), averageCPU: sqlite3_column_double(stmt, 3))
      }
    }
    sqlite3_finalize(stmt)
    for (s, dt) in pending where s.date >= since {
      t.download += s.download * dt
      t.upload += s.upload * dt
      t.written += s.diskWrite * dt
    }
    return t
  }
}
