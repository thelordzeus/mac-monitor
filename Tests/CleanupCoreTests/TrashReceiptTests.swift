import Darwin
import Foundation
import Testing

@testable import CleanupCore

struct TrashReceiptTests {
  private struct Fixture {
    let root: URL, original: URL, trash: URL, record: TrashRecord
    init() throws {
      let fm = FileManager.default
      let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
      root = URL(fileURLWithPath: try #require(ReviewFile.canonicalPath(temporary.path)))
      let parent = root.appendingPathComponent("original")
      let trashRoot = root.appendingPathComponent("trash")
      try fm.createDirectory(at: parent, withIntermediateDirectories: true)
      try fm.createDirectory(at: trashRoot, withIntermediateDirectories: true)
      original = parent.appendingPathComponent("payload.txt")
      trash = trashRoot.appendingPathComponent("payload.txt")
      try Data("restore this".utf8).write(to: original)
      try fm.moveItem(at: original, to: trash)
      var source = stat()
      var destination = stat()
      guard lstat(trash.path, &source) == 0, lstat(parent.path, &destination) == 0 else {
        throw POSIXError(.EIO)
      }
      record = .init(
        originalPath: original.path, trashPath: trash.path, device: source.st_dev,
        inode: source.st_ino, parentDevice: destination.st_dev, parentInode: destination.st_ino)
    }
    var roots: [String] { [trash.deletingLastPathComponent().path] }
    func remove() { try? FileManager.default.removeItem(at: root) }
  }
  @Test func restoresTrackedItemToOriginalParent() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try TrashRecovery.restore(fixture.record, roots: fixture.roots)
    #expect(try String(contentsOf: fixture.original) == "restore this")
    #expect(!FileManager.default.fileExists(atPath: fixture.trash.path))
    #expect(throws: TrashRecoveryError.self) {
      try TrashRecovery.restore(fixture.record, roots: fixture.roots)
    }
  }
  @Test func restoreNeverOverwritesOrMovesUntrackedTrash() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    #expect(throws: TrashRecoveryError.self) {
      try TrashRecovery.restore(fixture.record, roots: [])
    }
    try Data("keep this".utf8).write(to: fixture.original)
    #expect(throws: TrashRecoveryError.self) {
      try TrashRecovery.restore(fixture.record, roots: fixture.roots)
    }
    #expect(try String(contentsOf: fixture.original) == "keep this")
    #expect(try String(contentsOf: fixture.trash) == "restore this")
  }
  @Test func replacedTrashItemAndChangedOriginalParentAreRejected() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let held = fixture.root.appendingPathComponent("held.txt")
    try FileManager.default.moveItem(at: fixture.trash, to: held)
    try Data("replacement".utf8).write(to: fixture.trash)
    #expect(throws: TrashRecoveryError.self) {
      try TrashRecovery.restore(fixture.record, roots: fixture.roots)
    }
    try FileManager.default.removeItem(at: fixture.trash)
    try FileManager.default.moveItem(at: held, to: fixture.trash)
    let parent = fixture.original.deletingLastPathComponent()
    let heldParent = fixture.root.appendingPathComponent("held-parent")
    try FileManager.default.moveItem(at: parent, to: heldParent)
    try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: heldParent)
    #expect(throws: TrashRecoveryError.self) {
      try TrashRecovery.restore(fixture.record, roots: fixture.roots)
    }
    #expect(FileManager.default.fileExists(atPath: fixture.trash.path))
  }
  @Test func receiptsMergeRestoredStateWithoutDuplicatingCleanupAndReadOldHistory() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let store = CleanupHistoryStore(url: fixture.root.appendingPathComponent("history.json"))
    var win = CleanupWin(
      id: "cleanup", date: .now, title: "Moved item", paths: [fixture.original.path], before: nil,
      after: nil, bytes: 12, recovery: [fixture.record])
    var ledger = CleanupLedger()
    ledger.record(win)
    _ = try store.merge(ledger)
    win.recovery?[0].restoredAt = Date(timeIntervalSince1970: 1_000)
    ledger.record(win)
    _ = try store.merge(ledger)
    let loaded = try store.load()
    #expect(loaded.wins.count == 1)
    #expect(loaded.wins.first?.recovery?.first?.restoredAt == Date(timeIntervalSince1970: 1_000))
    let old = Data(
      "{\"wins\":[{\"id\":\"old\",\"date\":0,\"title\":\"Old cleanup\",\"paths\":[\"/example\"]}]}"
        .utf8)
    let decoded = try JSONDecoder().decode(CleanupLedger.self, from: old)
    #expect(decoded.wins.first?.recovery == nil)
  }
  @Test func leftoverCandidatesUseExactBundlePathsAndExcludeSharedContainers() {
    let paths = AppLeftoverScanner.approvedPaths(
      appPath: "/Applications/Test.app", bundleID: "com.example.test", home: "/home")
    #expect(paths.count == 5)
    #expect(paths.contains("/home/Library/Preferences/com.example.test.plist"))
    #expect(!paths.contains(where: { $0.contains("Containers") || $0.contains("/Documents/") }))
    #expect(
      AppLeftoverScanner.approvedPaths(
        appPath: "/Applications/Test.app", bundleID: "../escape", home: "/home") == [
          "/Applications/Test.app"
        ])
  }
  @Test func leftoverFingerprintDetectsFileChangesAndDoesNotFollowLinks() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let directory = fixture.root.appendingPathComponent("app-data")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("profile")
    try Data("one".utf8).write(to: file)
    try FileManager.default.createSymbolicLink(
      at: directory.appendingPathComponent("link"), withDestinationURL: fixture.root)
    let first = try AppLeftoverScanner.measure(directory.path)
    #expect(first.bytes < 1_000_000)
    try Data("different".utf8).write(to: file)
    #expect(try AppLeftoverScanner.measure(directory.path).fingerprint != first.fingerprint)
    #expect(throws: ReviewDeleteError.self) {
      try AppLeftoverScanner.measure(directory.appendingPathComponent("link").path)
    }
  }
}
