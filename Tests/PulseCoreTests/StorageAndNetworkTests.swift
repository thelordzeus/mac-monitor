import Darwin
import Foundation
import Testing

@testable import PulseCore

struct StorageAndNetworkTests {
  @Test func storageComparisonIncludesNewRemovedAndChangedPathsAndRejectsPartial() {
    let old = StorageSnapshot(
      root: "/root",
      entries: [.init(path: "/root/changed", bytes: 10), .init(path: "/root/removed", bytes: 80)],
      complete: true)
    let new = StorageSnapshot(
      root: "/root",
      entries: [.init(path: "/root/changed", bytes: 20), .init(path: "/root/new", bytes: 50)],
      complete: true)
    #expect(new.changes(since: old).map(\.delta) == [-80, 50, 10])
    #expect(
      StorageSnapshot(root: "/root", entries: new.entries, complete: false).changes(since: old)
        .isEmpty)
    #expect(
      StorageSnapshot(root: "/else", entries: new.entries, complete: true).changes(since: old)
        .isEmpty)
  }
  @Test func storageMapPreservesAreaAndProportions() {
    let entries = [
      StorageSize(path: "a", bytes: 60), .init(path: "b", bytes: 30), .init(path: "c", bytes: 10),
      .init(path: "zero", bytes: 0),
    ]
    let tiles = StorageMap.tiles(entries, width: 400, height: 200)
    #expect(tiles.count == 3)
    #expect(abs(tiles.reduce(0) { $0 + $1.width * $1.height } - 80000) < 0.001)
    for tile in tiles {
      #expect(
        tile.x >= 0 && tile.y >= 0 && tile.x + tile.width <= 400.001
          && tile.y + tile.height <= 200.001)
      #expect(abs(tile.width * tile.height / 80000 - Double(tile.entry.bytes) / 100) < 0.0001)
    }
    #expect(StorageMap.tiles(entries, width: 0, height: 200).isEmpty)
  }
  @Test func folderScanDoesNotFollowLinksOrDoubleCountHardLinksAndMarksLimits() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      .resolvingSymlinksInPath()
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    let file = root.appendingPathComponent("data")
    try Data(repeating: 1, count: 16384).write(to: file)
    try fm.linkItem(at: file, to: root.appendingPathComponent("hardlink"))
    try fm.createSymbolicLink(
      at: root.appendingPathComponent("symlink"),
      withDestinationURL: URL(fileURLWithPath: "/Applications"))
    var info = stat()
    #expect(lstat(file.path, &info) == 0)
    let scan = StorageScanner.scan(root: root.path)
    #expect(scan.complete)
    #expect(scan.bytes == UInt64(info.st_blocks) * 512)
    #expect(scan.entries.first(where: { $0.name == "symlink" })?.bytes == 0)
    #expect(!StorageScanner.scan(root: root.path, maximumEntries: 1).complete)
    #expect(!StorageScanner.scan(root: root.path, seconds: 0).complete)
    #expect(!StorageScanner.scan(root: root.appendingPathComponent("symlink").path).complete)
  }
  @Test func historyPrunesAndChoosesCompleteBaseline() {
    var history = StorageHistory()
    let date = Date(timeIntervalSince1970: 20e6)
    let old = StorageSnapshot(
      root: "/r", date: date.addingTimeInterval(-91 * 86400), entries: [], complete: true)
    let baseline = StorageSnapshot(
      root: "/r", date: date.addingTimeInterval(-100), entries: [], complete: true)
    let partial = StorageSnapshot(
      root: "/r", date: date.addingTimeInterval(-50), entries: [], complete: false)
    let current = StorageSnapshot(root: "/r", date: date, entries: [], complete: true)
    for scan in [old, baseline, partial, current] { history.record(scan) }
    #expect(history.snapshots.count == 3)
    #expect(history.previous(to: current)?.id == baseline.id)
  }
  @Test func hostValidationPreventsCommandOptionsAndURLs() {
    for host in ["apple.com", "1.1.1.1", "localhost", "::1", "2001:4860:4860::8888"] {
      #expect(NetworkDiagnostics.validHost(host))
    }
    for host in [
      "-c", "https://apple.com", "apple.com; touch x", "a b", "a..com", "", "-host.com",
      "host-.com", "a\n.com",
    ] { #expect(!NetworkDiagnostics.validHost(host)) }
  }
  @Test func pingParsingDistinguishesLossLatencyAndMissingReplies() {
    let stats = NetworkDiagnostics.pingStatistics(
      "5 packets transmitted, 4 packets received, 20.0% packet loss\nround-trip min/avg/max/stddev = 1.100/2.200/3.300/0.5 ms"
    )
    #expect(stats.loss == 20 && stats.latency == 2.2)
    let missing = NetworkDiagnostics.pingStatistics(
      "5 packets transmitted, 0 packets received, 100.0% packet loss")
    #expect(missing.loss == 100 && missing.latency == nil)
    #expect(NetworkDiagnostics.pingStatistics("could not resolve host").loss == nil)
  }
}
