import Foundation
import Testing

@testable import BlitzCleanIntegration

struct InventoryCacheTests {
  private let spotify = InventoryCacheOwner(name: "Spotify", applicationPath: "/Applications/Spotify.app",
    bundleIdentifier: "com.spotify.client", processNames: ["Spotify"])

  @Test func resolvesClosedAppsBundlePrefixesAndRuntimeAliases() {
    let catalog = InventoryCacheOwnerCatalog(applications: [
      .init(name: "Arc", path: "/Applications/Arc.app/Contents/Frameworks/Arc Helper.app", bundleIdentifier: "company.thebrowser.Browser.helper", executable: "Arc Helper"),
      .init(name: "Spotify", path: "/Applications/Spotify.app", bundleIdentifier: "com.spotify.client", executable: "Spotify"),
      .init(name: "Arc", path: "/Applications/Arc.app", bundleIdentifier: "company.thebrowser.Browser", executable: "Arc"),
      .init(name: "Codex", path: "/Applications/Codex.app", bundleIdentifier: "com.openai.codex", executable: "Codex"),
    ])
    #expect(catalog.owner(for: "/home/Library/Caches/com.spotify.client").applicationPath == "/Applications/Spotify.app")
    #expect(catalog.owner(for: "/home/Library/Caches/com.spotify.client.helper").name == "Spotify")
    #expect(catalog.owner(for: "/home/Library/Caches/Arc").applicationPath == "/Applications/Arc.app")
    #expect(catalog.owner(for: "/home/Library/Caches/company.thebrowser.Browser").applicationPath == "/Applications/Arc.app")
    #expect(catalog.owner(for: "/home/.cache/codex-runtimes").bundleIdentifier == "com.openai.codex")
    #expect(catalog.owner(for: "/home/.cache/codex-runtimes").processNames.contains("codex"))
    #expect(catalog.owner(for: "/home/Library/Caches/com.spotify.clientUnrelated").applicationPath == nil)
    #expect(catalog.owner(for: "/home/Library/Caches/unrecognized").name == "unrecognized")
    #expect(catalog.owner(for: "/home/.npm/_cacache").name == "npm")
  }

  @Test func manualReviewMovesRecentCacheToFixtureTrashAndKeepsAppData() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let cache = try fixture.cache("com.spotify.client")
    let support = fixture.home.appendingPathComponent("Library/Application Support/profile.txt")
    try FileManager.default.createDirectory(at: support.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("keep settings".utf8).write(to: support)
    let cleaner = fixture.cleaner()
    let candidate = try cleaner.prepare(.init(item: item(cache), owner: spotify), activity: .init())
    let win = try cleaner.trash(candidate, activity: .init())
    #expect(!FileManager.default.fileExists(atPath: cache.path))
    #expect(FileManager.default.fileExists(atPath: fixture.trash.appendingPathComponent("com.spotify.client/payload").path))
    #expect(try String(contentsOf: support) == "keep settings")
    #expect(win.paths == [cache.path])
    #expect(win.bytes == candidate.cache.tree.bytes)
  }

  @Test func rejectsCacheRootsPersonalFoldersAndTraversal() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    _ = try fixture.cache("valid")
    let personal = fixture.home.appendingPathComponent("Documents")
    try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
    let cleaner = fixture.cleaner()
    for path in [personal.path, fixture.home.appendingPathComponent("Library/Caches").path,
      fixture.home.path + "/Library/Caches/../../Documents"] {
      #expect(throws: CacheCleanError.self) {
        try cleaner.prepare(.init(item: item(URL(fileURLWithPath: path)), owner: spotify), activity: .init())
      }
    }
    #expect(FileManager.default.fileExists(atPath: personal.path))
  }

  @Test func rejectsLinkedRootAndNestedLinkWithoutFollowingPersonalData() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let cache = try fixture.cache("linked-child")
    let personal = fixture.home.appendingPathComponent("personal.txt")
    try Data("private".utf8).write(to: personal)
    try FileManager.default.createSymbolicLink(at: cache.appendingPathComponent("link"), withDestinationURL: personal)
    #expect(throws: CacheCleanError.self) {
      try fixture.cleaner().prepare(.init(item: item(cache), owner: spotify), activity: .init())
    }
    let rootAlias = fixture.home.appendingPathComponent(".cache")
    try FileManager.default.createSymbolicLink(at: rootAlias, withDestinationURL: cache)
    #expect(throws: CacheCleanError.self) {
      try fixture.cleaner().prepare(.init(item: item(rootAlias.appendingPathComponent("payload")), owner: spotify), activity: .init())
    }
    #expect(try String(contentsOf: personal) == "private")
  }

  @Test func rechecksRunningOwnerAndInteriorChangesBeforeMoving() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let cache = try fixture.cache("com.spotify.client")
    let cleaner = fixture.cleaner()
    let input = InventoryCacheInput(item: item(cache), owner: spotify)
    #expect(throws: CacheCleanError.self) {
      try cleaner.prepare(input, activity: .init(bundleIdentifiers: ["com.spotify.client"]))
    }
    let candidate = try cleaner.prepare(input, activity: .init())
    #expect(throws: CacheCleanError.self) {
      try cleaner.trash(candidate, activity: .init(processNames: ["Spotify"]))
    }
    try Data(repeating: 9, count: 8192).write(to: cache.appendingPathComponent("payload"))
    #expect(throws: CacheCleanError.self) { try cleaner.trash(candidate, activity: .init()) }
    #expect(FileManager.default.fileExists(atPath: cache.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.trash.path).isEmpty)
  }

  @Test func replacedDirectoryCannotUseOldReview() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let cache = try fixture.cache("replaced")
    let cleaner = fixture.cleaner()
    let candidate = try cleaner.prepare(.init(item: item(cache), owner: spotify), activity: .init())
    try FileManager.default.moveItem(at: cache, to: fixture.home.appendingPathComponent("original"))
    _ = try fixture.cache("replaced")
    #expect(throws: CacheCleanError.self) { try cleaner.trash(candidate, activity: .init()) }
    #expect(FileManager.default.fileExists(atPath: cache.path))
  }

  @Test func openCacheFileAndUnverifiedActivityBlockReview() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let cache = try fixture.cache("open")
    let handle = try FileHandle(forReadingFrom: cache.appendingPathComponent("payload"))
    defer { try? handle.close() }
    let nativeChecks = InventoryCacheCleaner(home: fixture.home.path)
    #expect(throws: CacheCleanError.self) {
      try nativeChecks.prepare(.init(item: item(cache), owner: spotify), activity: .init())
    }
    var unverified = fixture.cleaner()
    unverified.checkOpenFiles = { _ in throw CacheCleanError.unverified }
    #expect(throws: CacheCleanError.self) {
      try unverified.prepare(.init(item: item(cache), owner: spotify), activity: .init())
    }
    #expect(FileManager.default.fileExists(atPath: cache.path))
  }

  @Test func supportsIndividualCacheFilesAndOnlyTheExplicitPackageStores() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    _ = try fixture.cache("setup")
    let paths = [".cache/download.bin", ".npm/_cacache", "Library/pnpm/store"]
    for relative in paths {
      let url = fixture.home.appendingPathComponent(relative)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try Data(repeating: 8, count: 4096).write(to: url)
      let candidate = try fixture.cleaner().prepare(.init(item: item(url), owner: spotify), activity: .init())
      #expect(candidate.id == url.path)
    }
    let cleaner = fixture.cleaner()
    #expect(!cleaner.supports(fixture.home.appendingPathComponent(".npm").path))
    #expect(!cleaner.supports(fixture.home.appendingPathComponent(".npm/npmrc").path))
    #expect(!cleaner.supports(fixture.home.appendingPathComponent("Library/pnpm").path))
  }

  @Test @MainActor func cancellingPreparationDoesNotEnableRemoval() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let cache = try fixture.cache("slow")
    let driver = FixtureCacheDriver(failingTrash: [], preparationDelay: .milliseconds(100))
    let model = InventoryCacheModel(driver: driver)
    model.update(items: [item(cache)], catalog: .init(applications: []))
    model.selected = [cache.path]
    model.prepare()
    #expect(model.isPreparing)
    model.cancelPreparation()
    try await Task.sleep(for: .milliseconds(150))
    #expect(!model.isBusy)
    #expect(model.review.isEmpty)
    #expect(model.selected == [cache.path])
    #expect(await driver.trashPaths.isEmpty)
  }

  @Test @MainActor func bulkSelectionReviewCancelAndPartialFailureUseExactItems() async throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let paths = try ["first", "second", "unselected"].map { try fixture.cache($0) }
    let items = paths.map(item)
    let driver = FixtureCacheDriver(failingTrash: [paths[1].path])
    let model = InventoryCacheModel(driver: driver)
    model.update(items: items, catalog: .init(applications: []))
    model.selected = Set(paths.prefix(2).map(\.path))
    #expect(model.selectedItems.count == 2)
    model.prepare()
    try await wait { !model.isPreparing }
    #expect(Set(model.review.map(\.id)) == model.selected)
    model.cancelReview()
    #expect(model.review.isEmpty)
    #expect(await driver.trashPaths.isEmpty)
    #expect(model.selected.count == 2)
    model.prepare()
    try await wait { !model.isPreparing }
    let history = CleanupOverviewModel(.init(store: .init(url: fixture.home.appendingPathComponent("history.json")),
      scanRequest: .init(roots: [fixture.home.path], minimumBytes: 0, maxEntries: 100), synchronizesInBackground: false))
    var rescanned = false
    model.moveReviewed(history: history, onCompletion: { rescanned = true })
    try await wait { !model.isRemoving }
    #expect(await driver.trashPaths == paths.prefix(2).map(\.path))
    #expect(model.selected == [paths[1].path])
    #expect(model.failures[paths[1].path] != nil)
    #expect(history.ledger.wins.count == 1)
    #expect(history.ledger.wins.first?.paths == [paths[0].path])
    #expect(rescanned)
  }

  @MainActor private func wait(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
      if condition() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Cache operation did not finish")
  }

  private func item(_ url: URL) -> StorageItem {
    .init(name: url.lastPathComponent, path: url.path, bytes: 4096,
      cleanupKind: nil, cleanupAvailability: nil, lastActivityAt: nil, contentBytes: nil,
      nodeOrigin: nil, projectRootPath: nil, dependencyInstalledAt: nil, activeProcesses: nil)
  }

  private struct Fixture {
    let home: URL
    let trash: URL
    init() throws {
      let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appendingPathComponent("inventory-cache-test-\(UUID())")
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      home = URL(fileURLWithPath: try #require(ReviewFile.canonicalPath(root.path)))
      trash = home.appendingPathComponent("FixtureTrash")
      try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
    }
    func cache(_ name: String) throws -> URL {
      let path = home.appendingPathComponent("Library/Caches/" + name)
      try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
      try Data(repeating: 1, count: 4096).write(to: path.appendingPathComponent("payload"))
      return path
    }
    func cleaner() -> InventoryCacheCleaner {
      let trash = trash
      return .init(home: home.path, checkOpenFiles: { _ in }, moveToTrash: { path in
        try FileManager.default.moveItem(at: URL(fileURLWithPath: path),
          to: trash.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent))
      })
    }
    func remove() { try? FileManager.default.removeItem(at: home) }
  }
}

private actor FixtureCacheDriver: InventoryCacheDriver {
  let failingTrash: Set<String>
  let preparationDelay: Duration
  private(set) var trashPaths: [String] = []
  init(failingTrash: Set<String>, preparationDelay: Duration = .zero) {
    self.failingTrash = failingTrash
    self.preparationDelay = preparationDelay
  }
  func prepare(_ input: InventoryCacheInput) async throws -> InventoryCacheCandidate {
    if preparationDelay != .zero { try await Task.sleep(for: preparationDelay) }
    return .init(cache: .init(path: input.item.path,
      rule: .init(title: input.owner.name, path: "fixture", recipe: "fixture", owners: [], kind: .cache),
      tree: .init(fingerprint: "fixture", bytes: input.item.bytes, newest: .now)), owner: input.owner)
  }
  func trash(_ candidate: InventoryCacheCandidate) async throws -> CleanupWin {
    trashPaths.append(candidate.id)
    if failingTrash.contains(candidate.id) { throw CacheCleanError.busy }
    return .init(id: UUID().uuidString, date: .now, title: "Fixture cache moved",
      paths: [candidate.id], before: nil, after: nil, bytes: candidate.cache.tree.bytes)
  }
}
