import Darwin
import Foundation

public struct StorageSize: Codable, Identifiable, Equatable, Sendable {
  public var path: String, bytes: UInt64
  public var id: String { path }
  public var name: String { URL(fileURLWithPath: path).lastPathComponent }
  public init(path: String, bytes: UInt64) {
    self.path = path
    self.bytes = bytes
  }
}
public struct StorageSnapshot: Codable, Identifiable, Sendable {
  public var id = UUID()
  public let root: String, date: Date, entries: [StorageSize], complete: Bool, unreadable: Int
  public var bytes: UInt64 { entries.reduce(0) { $0 + $1.bytes } }
  public init(
    root: String, date: Date = .now, entries: [StorageSize], complete: Bool, unreadable: Int = 0
  ) {
    self.root = root
    self.date = date
    self.entries = entries
    self.complete = complete
    self.unreadable = unreadable
  }
  public func changes(since previous: Self) -> [StorageChange] {
    guard complete, previous.complete, root == previous.root else { return [] }
    let old = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.path, $0.bytes) })
    let new = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.bytes) })
    return Set(old.keys).union(new.keys).map { path in
      StorageChange(path: path, before: old[path, default: 0], after: new[path, default: 0])
    }.filter { $0.before != $0.after }.sorted { abs($0.delta) > abs($1.delta) }
  }
}
public struct StorageChange: Identifiable, Sendable {
  public let path: String, before: UInt64, after: UInt64
  public var id: String { path }
  public var delta: Double { Double(after) - Double(before) }
}
public enum StorageScanner {
  /// A bounded, read-only scan of allocated bytes. Links and other volumes are not followed.
  public static func scan(root: String, maximumEntries: Int = 200_000, seconds: Double = 30)
    -> StorageSnapshot
  {
    let fm = FileManager.default
    let url = URL(fileURLWithPath: root).standardizedFileURL
    var rootInfo = stat()
    guard lstat(url.path, &rootInfo) == 0, rootInfo.st_mode & S_IFMT == S_IFDIR,
      url.resolvingSymlinksInPath().path == url.path
    else {
      return .init(root: root, entries: [], complete: false, unreadable: 1)
    }
    let deadline = Date().addingTimeInterval(seconds)
    var visited = 0
    var unreadable = 0
    var limited = false
    var seen = Set<String>()
    var totals: [String: UInt64] = [:]
    guard let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    else {
      return .init(root: root, entries: [], complete: false, unreadable: 1)
    }
    for child in children.sorted(by: { $0.path < $1.path }) {
      if Task.isCancelled || Date() >= deadline || visited >= maximumEntries {
        limited = true
        break
      }
      var pending = [child]
      var cursor = 0
      totals[child.path] = 0
      while cursor < pending.count {
        if Task.isCancelled || Date() >= deadline || visited >= maximumEntries {
          limited = true
          break
        }
        let next = pending[cursor]
        cursor += 1
        visited += 1
        var info = stat()
        guard lstat(next.path, &info) == 0 else {
          unreadable += 1
          continue
        }
        if info.st_mode & S_IFMT == S_IFLNK { continue }
        guard info.st_dev == rootInfo.st_dev else {
          unreadable += 1
          continue
        }
        let identity = "\(info.st_dev):\(info.st_ino)"
        if seen.insert(identity).inserted {
          totals[child.path, default: 0] += UInt64(max(0, info.st_blocks)) * 512
        }
        if info.st_mode & S_IFMT == S_IFDIR {
          if let nested = try? fm.contentsOfDirectory(at: next, includingPropertiesForKeys: nil) {
            pending.append(contentsOf: nested)
          } else {
            unreadable += 1
          }
        }
      }
    }
    return .init(
      root: root,
      entries: totals.map { .init(path: $0.key, bytes: $0.value) }.sorted { $0.bytes > $1.bytes },
      complete: !limited && unreadable == 0, unreadable: unreadable)
  }
}
public struct StorageHistory: Codable, Sendable {
  public var snapshots: [StorageSnapshot] = []
  public init() {}
  public mutating func record(_ snapshot: StorageSnapshot) {
    snapshots.append(snapshot)
    snapshots = Array(
      snapshots.filter { $0.date > snapshot.date.addingTimeInterval(-90 * 86400) }.sorted {
        $0.date > $1.date
      }.prefix(300))
  }
  public func previous(to snapshot: StorageSnapshot) -> StorageSnapshot? {
    snapshots.first { $0.root == snapshot.root && $0.complete && $0.date < snapshot.date }
  }
}
public struct StorageTile: Identifiable, Sendable {
  public let entry: StorageSize, x: Double, y: Double, width: Double, height: Double
  public var id: String { entry.id }
}
public enum StorageMap {
  /// Recursive area partitioning; each clickable tile's area represents its share of allocated bytes.
  public static func tiles(_ entries: [StorageSize], width: Double, height: Double) -> [StorageTile]
  {
    guard width > 0, height > 0 else { return [] }
    func partition(_ rows: [StorageSize], x: Double, y: Double, w: Double, h: Double)
      -> [StorageTile]
    {
      guard !rows.isEmpty else { return [] }
      if rows.count == 1 { return [.init(entry: rows[0], x: x, y: y, width: w, height: h)] }
      let total = rows.reduce(0.0) { $0 + Double($1.bytes) }
      var leftBytes = 0.0
      var split = 1
      for i in 0..<(rows.count - 1) {
        leftBytes += Double(rows[i].bytes)
        split = i + 1
        if leftBytes >= total / 2 { break }
      }
      let ratio = total > 0 ? leftBytes / total : Double(split) / Double(rows.count)
      if w >= h {
        return partition(Array(rows.prefix(split)), x: x, y: y, w: w * ratio, h: h)
          + partition(
            Array(rows.dropFirst(split)), x: x + w * ratio, y: y, w: w * (1 - ratio), h: h)
      }
      return partition(Array(rows.prefix(split)), x: x, y: y, w: w, h: h * ratio)
        + partition(Array(rows.dropFirst(split)), x: x, y: y + h * ratio, w: w, h: h * (1 - ratio))
    }
    return partition(entries.filter { $0.bytes > 0 }, x: 0, y: 0, w: width, h: height)
  }
}
