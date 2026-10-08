import AppKit
import CryptoKit
import Darwin
import Foundation

struct AppLeftover: Identifiable, Sendable {
  let path: String, title: String, detail: String, bytes: UInt64, fingerprint: String
  var id: String { path }
}
struct AppLeftoverReview: Sendable {
  let appPath: String, bundleID: String, name: String, candidates: [AppLeftover], notes: [String]
}
enum AppLeftoverScanner {
  static func approvedPaths(appPath: String, bundleID: String, home: String) -> [String] {
    guard
      bundleID.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{1,200}$", options: .regularExpression) != nil
    else { return [appPath] }
    return [
      appPath, home + "/Library/Caches/" + bundleID,
      home + "/Library/Preferences/" + bundleID + ".plist",
      home + "/Library/Application Support/" + bundleID,
      home + "/Library/Saved Application State/" + bundleID + ".savedState",
    ]
  }
  static func review(appPath: String, home: String = NSHomeDirectory()) throws -> AppLeftoverReview
  {
    guard appPath.hasSuffix(".app"),
      ["/Applications/", home + "/Applications/"].contains(where: { appPath.hasPrefix($0) }),
      ReviewFile.canonicalPath(appPath) == appPath, let bundle = Bundle(path: appPath),
      let id = bundle.bundleIdentifier,
      id != Bundle.main.bundleIdentifier
    else { throw ReviewDeleteError.protected }
    let name =
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? bundle.object(
        forInfoDictionaryKey: "CFBundleName") as? String
      ?? URL(fileURLWithPath: appPath).deletingPathExtension().lastPathComponent
    var candidates: [AppLeftover] = []
    var notes: [String] = []
    for path in approvedPaths(appPath: appPath, bundleID: id, home: home)
    where FileManager.default.fileExists(atPath: path) {
      do {
        let measurement = try measure(path)
        let kind =
          path == appPath
          ? "App bundle"
          : path.contains("/Caches/")
            ? "Cache"
            : path.contains("/Preferences/")
              ? "Preferences"
              : path.contains("/Saved Application State/") ? "Saved state" : "Support data"
        candidates.append(
          .init(
            path: path, title: kind,
            detail: kind == "Support data"
              ? "May contain profiles or personal app data. Review before selecting."
              : "Matched to \(id)", bytes: measurement.bytes, fingerprint: measurement.fingerprint))
      } catch { notes.append("Kept \(path): \(error.localizedDescription)") }
    }
    return .init(appPath: appPath, bundleID: id, name: name, candidates: candidates, notes: notes)
  }
  static func measure(_ path: String) throws -> (bytes: UInt64, fingerprint: String) {
    guard ReviewFile.canonicalPath(path) == path else { throw ReviewDeleteError.changed }
    var pending = [path]
    var index = 0
    var bytes: UInt64 = 0
    var hash = SHA256()
    var seen = Set<String>()
    let deadline = Date.now.addingTimeInterval(15)
    while index < pending.count {
      guard index < 150_000, Date.now < deadline, !Task.isCancelled else {
        throw ReviewDeleteError.unverified
      }
      let current = pending[index]
      index += 1
      var info = stat()
      guard lstat(current, &info) == 0 else { throw ReviewDeleteError.changed }
      let identity = "\(info.st_dev):\(info.st_ino)"
      hash.update(
        data: Data(
          "\(current.dropFirst(path.count))|\(identity)|\(info.st_mode)|\(info.st_size)|\(info.st_mtimespec.tv_sec)|\(info.st_mtimespec.tv_nsec)\n"
            .utf8))
      if seen.insert(identity).inserted { bytes += UInt64(max(0, info.st_blocks)) * 512 }
      if info.st_mode & S_IFMT == S_IFDIR {
        pending.append(
          contentsOf: try FileManager.default.contentsOfDirectory(atPath: current).sorted().map {
            current + "/" + $0
          })
      }
    }
    return (bytes, hash.finalize().map { String(format: "%02x", $0) }.joined())
  }
  static func trash(
    _ candidate: AppLeftover, review: AppLeftoverReview, home: String = NSHomeDirectory()
  ) throws -> CleanupWin {
    guard
      approvedPaths(appPath: review.appPath, bundleID: review.bundleID, home: home).contains(
        candidate.path),
      review.candidates.contains(where: {
        $0.path == candidate.path && $0.fingerprint == candidate.fingerprint
      })
    else { throw ReviewDeleteError.protected }
    let check = CleanupActivity.command(
      DirectoryCheckForLeftovers.isDirectory(candidate.path)
        ? ["-nP", "+D", candidate.path] : ["-nP", "--", candidate.path])
    if check.status == 0 { throw ReviewDeleteError.busy([]) }
    guard check.status == 1, check.output.isEmpty else { throw ReviewDeleteError.unverified }
    let current = try measure(candidate.path)
    guard current.fingerprint == candidate.fingerprint else { throw ReviewDeleteError.changed }
    let before = CleanupVolume.read(candidate.path)
    let receipt = try TrashRecovery.trash(candidate.path)
    return .init(
      id: UUID().uuidString, date: .now,
      title: "Moved \(review.name) · \(candidate.title) to Trash", paths: [candidate.path],
      before: before, after: before.flatMap { CleanupVolume.read($0.path) }, bytes: current.bytes,
      recovery: receipt.map { [$0] })
  }
}
private enum DirectoryCheckForLeftovers {
  static func isDirectory(_ path: String) -> Bool {
    var info = stat()
    return lstat(path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
  }
}
@MainActor final class AppLeftoverModel: ObservableObject {
  @Published var review: AppLeftoverReview?
  @Published var selected = Set<String>()
  @Published var busy = false
  @Published var status: String?
  func scan(_ path: String) {
    guard !busy else { return }
    busy = true
    review = nil
    status = "Finding app files…"
    Task {
      do {
        let result = try await Task.detached(priority: .utility) {
          try AppLeftoverScanner.review(appPath: path)
        }.value
        review = result
        selected = result.candidates.contains(where: { $0.path == path }) ? [path] : []
        status = nil
      } catch { status = error.localizedDescription }
      busy = false
    }
  }
  func remove(history: CleanupOverviewModel, finished: @escaping () -> Void) {
    guard !busy, let review, !selected.isEmpty else { return }
    busy = true
    let candidates = review.candidates.filter { selected.contains($0.path) }
    Task {
      var errors: [String] = []
      var moved = Set<String>()
      for candidate in candidates {
        guard
          !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == review.bundleID || $0.bundleURL?.path == review.appPath
          })
        else {
          errors.append("Quit \(review.name) before removing its files.")
          break
        }
        do {
          let win = try await Task.detached(priority: .utility) {
            try AppLeftoverScanner.trash(candidate, review: review)
          }.value
          history.record(win)
          moved.insert(candidate.path)
        } catch { errors.append("\(candidate.title): \(error.localizedDescription)") }
      }
      self.review = .init(
        appPath: review.appPath, bundleID: review.bundleID, name: review.name,
        candidates: review.candidates.filter { !moved.contains($0.path) }, notes: review.notes)
      selected.subtract(moved)
      busy = false
      status =
        "Moved \(moved.count) items to Trash. "
        + (errors.isEmpty
          ? "Restore tracked items in Cleanup → History." : errors.joined(separator: " "))
      if !moved.isEmpty { finished() }
    }
  }
}
