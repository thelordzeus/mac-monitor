import AppKit
import Darwin
import Foundation

struct TrashRecord: Codable, Equatable, Identifiable, Sendable {
  let originalPath: String, trashPath: String
  let device: Int32, inode: UInt64, parentDevice: Int32, parentInode: UInt64
  var restoredAt: Date? = nil
  var id: String { trashPath }
}
enum TrashRecoveryError: LocalizedError {
  case changed, destination, location, permission
  var errorDescription: String? {
    switch self {
    case .changed: "The item or its original folder changed, or the item is no longer in Trash."
    case .destination: "An item already exists at the original path. Nothing was overwritten."
    case .location: "The recorded item is outside this user's Trash locations."
    case .permission:
      "macOS blocked access to the item or its Trash location. Review Full Disk Access in Cleanup → Setup, then try again."
    }
  }
}
enum TrashRecovery {
  static func trash(_ path: String) throws -> TrashRecord? {
    let url = URL(fileURLWithPath: path)
    let parent = url.deletingLastPathComponent()
    var parentInfo = stat()
    var original = stat()
    guard ReviewFile.canonicalPath(path) == path, lstat(path, &original) == 0,
      original.st_mode & S_IFMT != S_IFLNK, lstat(parent.path, &parentInfo) == 0
    else { throw TrashRecoveryError.changed }
    var destination: NSURL?
    try FileManager.default.trashItem(at: url, resultingItemURL: &destination)
    guard let target = destination as URL? else { return nil }
    var moved = stat()
    guard lstat(target.path, &moved) == 0, let physical = ReviewFile.canonicalPath(target.path)
    else { return nil }
    return TrashRecord(
      originalPath: path, trashPath: physical,
      device: moved.st_dev, inode: moved.st_ino, parentDevice: parentInfo.st_dev,
      parentInode: parentInfo.st_ino)
  }
  static var roots: [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let volumes = (try? FileManager.default.contentsOfDirectory(atPath: "/Volumes")) ?? []
    return [home.appendingPathComponent(".Trash").path]
      + volumes.map { "/Volumes/\($0)/.Trashes/\(getuid())" }
  }
  static func validate(_ record: TrashRecord, roots: [String] = roots) throws {
    guard record.restoredAt == nil,
      roots.contains(where: { root in
        guard let physical = ReviewFile.canonicalPath(root) else { return false }
        return record.trashPath.hasPrefix(physical + "/")
      })
    else { throw TrashRecoveryError.location }
    let parent = URL(fileURLWithPath: record.originalPath).deletingLastPathComponent().path
    var target = stat()
    var parentInfo = stat()
    var existing = stat()
    guard ReviewFile.canonicalPath(record.trashPath) == record.trashPath,
      lstat(record.trashPath, &target) == 0, target.st_mode & S_IFMT != S_IFLNK,
      target.st_dev == record.device, target.st_ino == record.inode,
      ReviewFile.canonicalPath(parent) == parent, lstat(parent, &parentInfo) == 0,
      parentInfo.st_dev == record.parentDevice, parentInfo.st_ino == record.parentInode
    else { throw TrashRecoveryError.changed }
    if lstat(record.originalPath, &existing) == 0 { throw TrashRecoveryError.destination }
    guard errno == ENOENT else { throw TrashRecoveryError.changed }
  }
  private static func accessError() -> TrashRecoveryError {
    errno == EPERM || errno == EACCES ? .permission : .changed
  }
  static func restore(_ record: TrashRecord, roots: [String] = roots) throws {
    try validate(record, roots: roots)
    let source = URL(fileURLWithPath: record.trashPath)
    let target = URL(fileURLWithPath: record.originalPath)
    // These handles anchor identity checks and relative renames. Directory contents are not read.
    let from = open(source.deletingLastPathComponent().path, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
    guard from >= 0 else { throw accessError() }
    let to = open(target.deletingLastPathComponent().path, O_EVTONLY | O_DIRECTORY | O_NOFOLLOW)
    guard to >= 0 else {
      let error = accessError()
      close(from)
      throw error
    }
    defer {
      close(from)
      close(to)
    }
    var current = stat()
    var parent = stat()
    guard fstatat(from, source.lastPathComponent, &current, AT_SYMLINK_NOFOLLOW) == 0,
      current.st_ino == record.inode, current.st_dev == record.device,
      fstat(to, &parent) == 0, parent.st_ino == record.parentInode,
      parent.st_dev == record.parentDevice
    else { throw TrashRecoveryError.changed }
    guard
      renameatx_np(
        from, source.lastPathComponent, to, target.lastPathComponent, UInt32(RENAME_EXCL)) == 0
    else {
      if errno == EEXIST { throw TrashRecoveryError.destination }
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }
}
