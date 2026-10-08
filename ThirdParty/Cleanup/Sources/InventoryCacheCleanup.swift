import AppKit
import Foundation

struct InventoryCacheInput: Sendable {
  let item: StorageItem
  let owner: InventoryCacheOwner
}

struct InventoryCacheCandidate: Identifiable, Sendable {
  let cache: CacheCandidate
  let owner: InventoryCacheOwner
  var id: String { cache.path }
}

struct InventoryCacheActivity: Sendable {
  var processNames: Set<String> = []
  var bundleIdentifiers: Set<String> = []

  func check(_ owner: InventoryCacheOwner) throws {
    guard processNames.isDisjoint(with: owner.processNames),
      owner.bundleIdentifier.map({ !bundleIdentifiers.contains($0) }) ?? true
    else { throw CacheCleanError.busy }
  }
}

/// Manual Inventory cleanup is recoverable. It does not relax automatic cleanup's age rules.
struct InventoryCacheCleaner: Sendable {
  let home: String
  var checkOpenFiles: @Sendable (String) throws -> Void = { try Self.nativeOpenFileCheck($0) }
  var moveToTrash: (@Sendable (String) throws -> Void)? = nil

  func supports(_ path: String) -> Bool {
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
    return [home + "/Library/Caches", home + "/.cache"].contains(parent)
      || [home + "/Library/pnpm/store", home + "/.npm/_cacache"].contains(path)
  }

  private func validate(_ candidate: CacheCandidate) throws {
    guard supports(candidate.path) else { throw CacheCleanError.outsideRoot }
    try CacheCleaner.validateLocation(candidate)
  }

  func prepare(_ input: InventoryCacheInput, activity: InventoryCacheActivity) throws
    -> InventoryCacheCandidate
  {
    let path = input.item.path
    let rule = CacheRule(title: input.owner.name + " cache",
      path: URL(fileURLWithPath: path).deletingLastPathComponent().path,
      recipe: "Apps recreate cached data when needed.", owners: input.owner.processNames, kind: .cache)
    let initial = CacheCandidate(path: path, rule: rule,
      tree: .init(fingerprint: "", bytes: 0, newest: .distantPast))
    try validate(initial)
    try activity.check(input.owner)
    try checkOpenFiles(path)
    let tree = try CacheCleaner.tree(.init(path: path, deadline: .now.addingTimeInterval(10)))
    try validate(initial)
    return .init(cache: .init(path: path, rule: rule, tree: tree), owner: input.owner)
  }

  func trash(_ candidate: InventoryCacheCandidate, activity: InventoryCacheActivity) throws
    -> CleanupWin
  {
    try validate(candidate.cache)
    try activity.check(candidate.owner)
    try checkOpenFiles(candidate.id)
    let current = try CacheCleaner.tree(.init(path: candidate.id, deadline: .now.addingTimeInterval(15)))
    guard current == candidate.cache.tree else { throw CacheCleanError.changed }
    try validate(candidate.cache)
    try checkOpenFiles(candidate.id)
    let before = CleanupVolume.read(candidate.id)
    let receipt: TrashRecord?
    if let moveToTrash { try moveToTrash(candidate.id); receipt = nil }
    else { receipt = try TrashRecovery.trash(candidate.id) }
    return .init(id: UUID().uuidString, date: .now,
      title: "Moved \(candidate.owner.name) cache to Trash", paths: [candidate.id],
      before: before, after: before.flatMap { CleanupVolume.read($0.path) }, bytes: current.bytes, recovery: receipt.map { [$0] })
  }

  private static func nativeOpenFileCheck(_ path: String) throws {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      throw CacheCleanError.changed
    }
    let result = CleanupActivity.command(
      isDirectory.boolValue ? ["-nP", "+D", path] : ["-nP", "--", path])
    if result.status == 0 { throw CacheCleanError.busy }
    guard result.status == 1, result.output.isEmpty else { throw CacheCleanError.unverified }
  }
}

protocol InventoryCacheDriver: Sendable {
  func prepare(_ input: InventoryCacheInput) async throws -> InventoryCacheCandidate
  func trash(_ candidate: InventoryCacheCandidate) async throws -> CleanupWin
}

struct NativeInventoryCacheDriver: InventoryCacheDriver {
  private var cleaner: InventoryCacheCleaner {
    .init(home: FileManager.default.homeDirectoryForCurrentUser.path)
  }

  private func activity() async throws -> InventoryCacheActivity {
    let identifiers = await MainActor.run {
      Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
    let processes = try await Task.detached(priority: .utility) { try CacheCleaner.processes() }.value
    return .init(processNames: processes, bundleIdentifiers: identifiers)
  }

  func prepare(_ input: InventoryCacheInput) async throws -> InventoryCacheCandidate {
    let activity = try await activity()
    let cleaner = cleaner
    return try await Task.detached(priority: .utility) {
      try cleaner.prepare(input, activity: activity)
    }.value
  }

  func trash(_ candidate: InventoryCacheCandidate) async throws -> CleanupWin {
    let activity = try await activity()
    let cleaner = cleaner
    return try await Task.detached(priority: .utility) {
      try cleaner.trash(candidate, activity: activity)
    }.value
  }
}

@MainActor
final class InventoryCacheModel: ObservableObject {
  @Published var selected: Set<String> = []
  @Published private(set) var owners: [String: InventoryCacheOwner] = [:]
  @Published private(set) var review: [InventoryCacheCandidate] = []
  @Published private(set) var failures: [String: String] = [:]
  @Published private(set) var isPreparing = false
  @Published private(set) var isRemoving = false
  @Published private(set) var status: String?
  private var items: [StorageItem] = []
  private let driver: any InventoryCacheDriver
  private var preparation: Task<Void, Never>?

  init(driver: any InventoryCacheDriver = NativeInventoryCacheDriver()) { self.driver = driver }
  var isBusy: Bool { isPreparing || isRemoving }
  var selectedItems: [StorageItem] { items.filter { selected.contains($0.path) } }
  var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + $1.bytes } }
  var reviewedBytes: UInt64 { review.reduce(0) { $0 + $1.cache.tree.bytes } }

  func update(items: [StorageItem], catalog: InventoryCacheOwnerCatalog) {
    self.items = items
    owners = Dictionary(uniqueKeysWithValues: items.map { ($0.path, catalog.owner(for: $0.path)) })
    selected.formIntersection(items.map(\.path))
  }

  func prepare() {
    guard !isBusy, !selectedItems.isEmpty, review.isEmpty else { return }
    let inputs = selectedItems.compactMap { item in
      owners[item.path].map { InventoryCacheInput(item: item, owner: $0) }
    }
    isPreparing = true
    status = "Checking selected caches…"
    failures = [:]
    preparation = Task {
      var prepared: [InventoryCacheCandidate] = []
      for (index, input) in inputs.enumerated() {
        guard !Task.isCancelled else { return }
        status = "Checking \(input.owner.name) · \(index + 1) of \(inputs.count)"
        do {
          let candidate = try await driver.prepare(input)
          guard !Task.isCancelled else { return }
          prepared.append(candidate)
        } catch {
          guard !Task.isCancelled else { return }
          failures[input.item.path] = error.localizedDescription
        }
      }
      review = prepared
      isPreparing = false
      status = failures.isEmpty ? nil
        : "\(failures.count) selected \(failures.count == 1 ? "cache was" : "caches were") kept. See the reasons in the list."
    }
  }

  func cancelPreparation() {
    preparation?.cancel()
    isPreparing = false
    status = "Cache review cancelled. Nothing was moved."
  }

  func cancelReview() { review = [] }

  func moveReviewed(history: CleanupOverviewModel, onCompletion: @escaping @MainActor () -> Void) {
    guard !isBusy, !review.isEmpty else { return }
    let candidates = review
    review = []
    isRemoving = true
    Task {
      var moved = 0
      var bytes: UInt64 = 0
      for (index, candidate) in candidates.enumerated() {
        status = "Moving \(candidate.owner.name) cache · \(index + 1) of \(candidates.count)"
        do {
          let win = try await driver.trash(candidate)
          history.record(win)
          selected.remove(candidate.id)
          failures[candidate.id] = nil
          moved += 1
          bytes += candidate.cache.tree.bytes
        } catch {
          failures[candidate.id] = error.localizedDescription
        }
      }
      isRemoving = false
      status = "Moved \(moved) \(moved == 1 ? "cache" : "caches") (\(ByteText.full(bytes))) to Trash."
        + (failures.isEmpty ? " Empty Trash to reclaim space."
          : " \(failures.count) kept; see the reasons in the list.")
      if moved > 0 { onCompletion() }
    }
  }
}
