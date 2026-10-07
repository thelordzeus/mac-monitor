import AppKit
import Combine
import SwiftUI

/// Values supplied by Mac Pulse's collector. Cleanup does not run a second stats timer.
public struct CleanupMetrics {
  public var diskAvailable: Double
  public var diskTotal: Double
  public var ramAvailable: Double
  public var ramTotal: Double
  public var cpuPercent: Double
  public var pressure: String
  public var date: Date

  public init(diskAvailable: Double, diskTotal: Double, ramAvailable: Double,
              ramTotal: Double, cpuPercent: Double, pressure: String, date: Date) {
    self.diskAvailable = diskAvailable
    self.diskTotal = diskTotal
    self.ramAvailable = ramAvailable
    self.ramTotal = ramTotal
    self.cpuPercent = cpuPercent
    self.pressure = pressure
    self.date = date
  }

  private func bytes(_ value: Double) -> UInt64 {
    guard value.isFinite, value > 0 else { return 0 }
    return UInt64(min(value, Double(Int64.max)))
  }

  var snapshot: SystemSnapshot {
    let level: MemoryPressureLevel = pressure == "Critical" ? .critical
      : ["Warning", "Elevated"].contains(pressure) ? .warning
      : pressure == "Normal" ? .normal : .unknown
    return SystemSnapshot(SystemSnapshotInput(diskAvailable: bytes(diskAvailable), diskTotal: bytes(diskTotal),
      ramAvailable: bytes(ramAvailable), ramTotal: bytes(ramTotal), memoryPressure: level,
      cpuUsage: cpuPercent.isFinite ? min(1, max(0, cpuPercent / 100)) : nil,
      thermalStatus: .unknown, updatedAt: date))
  }
}

enum CleanupSection: String, CaseIterable, Identifiable {
  case cleanup = "Cleanup", browse = "Browse", inventory = "Inventory"
  case files = "Files & media", recovery = "Revive apps", memory = "AI & apps"
  case projects = "Projects", setup = "Setup"
  var id: Self { self }
  var symbol: String {
    switch self {
    case .cleanup: "sparkles"
    case .browse: "folder"
    case .inventory: "internaldrive"
    case .files: "photo.on.rectangle"
    case .recovery: "waveform.path.ecg"
    case .memory: "memorychip"
    case .projects: "terminal"
    case .setup: "gearshape"
    }
  }
}

@MainActor
public final class CleanupWorkspace: ObservableObject {
  public nonisolated static let openNotification = Notification.Name("MacMonitor.openCleanup")
  @Published var section = CleanupSection.cleanup
  @Published var hasOpenedReview = false
  let monitor = SystemMonitor(externallyManaged: true)
  let caches = QuickCleanModel()
  let storage = StorageBreakdownModel()
  let docker = DockerStorageModel()
  let folders = FolderExplorerModel(path: FileManager.default.homeDirectoryForCurrentUser.path)
  let worktrees = DeveloperBrowserModel()
  let processes = DevProcessModel(start: false)
  let projects = WorkspaceController()
  let navigation = CleanNavigation()
  let recovery = AppRecoveryModel()
  private var memoryModel: MemoryRescueModel?
  private var subscriptions = Set<AnyCancellable>()
  var memory: MemoryRescueModel {
    if let memoryModel { return memoryModel }
    let model = MemoryRescueModel()
    memoryModel = model
    return model
  }

  public init() {
    navigation.storagePage = .cleanup
    for name in [Notification.Name.openMemoryRescue, .openStorageReview, .openWorkspace, .openAppRecovery] {
      NotificationCenter.default.publisher(for: name).receive(on: RunLoop.main)
        .sink { [weak self] notification in
          MainActor.assumeIsolated {
            self?.open(notification.name == .openStorageReview ? .cleanup
              : notification.name == .openWorkspace ? .projects
              : notification.name == .openAppRecovery ? .recovery : .memory)
            NotificationCenter.default.post(name: Self.openNotification, object: nil)
          }
        }.store(in: &subscriptions)
    }
  }

  public func update(_ values: CleanupMetrics) { monitor.applyExternal(values.snapshot) }

  func open(_ target: CleanupSection) {
    if target != .browse { folders.cancelScan() }
    if target != .files { storage.overview.cancelScan() }
    section = target
    switch target {
    case .cleanup:
      hasOpenedReview = true
      navigation.storagePage = .cleanup
      processes.activate()
    case .browse: navigation.storagePage = .browse
    case .inventory: navigation.storagePage = .mac
    case .memory, .projects: processes.activate()
    default: break
    }
  }

  public func shutdown() {
    folders.cancelScan()
    storage.overview.cancelScan()
    worktrees.cancel()
    processes.stopMonitoring()
    memoryModel?.recordShutdown()
  }

  func showTools() {
    folders.cancelScan()
    storage.overview.cancelScan()
    section = .cleanup
    hasOpenedReview = false
  }
}

/// The public integration surface. Upstream cleanup engines stay internal to this module.
@MainActor
public struct MacMonitorCleanupView: View {
  @ObservedObject private var workspace: CleanupWorkspace
  private let exporting: Bool

  public init(workspace: CleanupWorkspace, exporting: Bool = false) {
    self.workspace = workspace
    self.exporting = exporting
  }

  public var body: some View {
    VStack(spacing: 0) {
      hero.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 16)
      Group {
        if exporting {
          sectionButtons.frame(maxWidth: .infinity, alignment: .leading)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            sectionButtons
          }
        }
      }.padding(.horizontal, 24).padding(.bottom, 8)
      content.frame(maxWidth: .infinity, maxHeight: .infinity)
    }.background(BlitzUI.canvasBackground).tint(BlitzUI.mint)
      .blitzDropdownHost()
      .onChange(of: workspace.navigation.storagePage) { _, page in
        guard [.cleanup, .browse, .inventory].contains(workspace.section) else { return }
        workspace.section = page == .cleanup ? .cleanup : page == .mac ? .inventory : .browse
      }
  }

  private var sectionButtons: some View {
    HStack(spacing: 4) {
      Button { workspace.showTools() } label: {
        Image(systemName: "house").font(.system(size: 12, weight: .medium))
          .foregroundStyle(BlitzUI.secondaryText).frame(width: 34, height: 34)
      }.buttonStyle(.plain).help("All cleanup tools").accessibilityLabel("All cleanup tools")
      ForEach(CleanupSection.allCases) { section in
        Button { workspace.open(section) } label: {
          Label(section.rawValue, systemImage: section.symbol)
            .font(.system(size: 12, weight: .medium)).fixedSize()
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(workspace.section == section ? BlitzUI.mint : BlitzUI.secondaryText)
            .background(workspace.section == section ? BlitzUI.mint.opacity(0.16) : .clear,
              in: Capsule())
        }.buttonStyle(.plain)
          .accessibilityAddTraits(workspace.section == section ? .isSelected : [])
      }
    }.padding(4).background(BlitzUI.panelBackground, in: Capsule())
  }

  private var hero: some View {
    HStack(spacing: 20) {
      Image(systemName: "sparkles").font(.system(size: 25, weight: .medium))
        .foregroundStyle(BlitzUI.mint).frame(width: 58, height: 58)
        .background(BlitzUI.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 16))
      VStack(alignment: .leading, spacing: 6) {
        Text("A little room to breathe").font(.system(size: 22, weight: .semibold))
        Text("Storage, cleanup and app recovery")
          .font(.system(size: 13)).foregroundStyle(BlitzUI.secondaryText)
      }
      Spacer(minLength: 16)
      VStack(alignment: .trailing, spacing: 4) {
        Text(ByteText.full(workspace.monitor.snapshot.diskAvailable))
          .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
        Text("available on your Mac").font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
      }
    }.padding(24).background(BlitzUI.panelBackground, in: RoundedRectangle(cornerRadius: 24))
  }

  @ViewBuilder private var content: some View {
    if exporting || (workspace.section == .cleanup && !workspace.hasOpenedReview) {
      welcome
    } else {
      switch workspace.section {
      case .cleanup, .browse, .inventory:
        BlitzStorageView(monitor: workspace.monitor, cleanup: workspace.caches,
          storage: workspace.storage, navigation: workspace.navigation, docker: workspace.docker,
          folders: workspace.folders, worktrees: WorktreeSources(model: workspace.worktrees,
            processes: workspace.processes, workspaces: workspace.projects), showsNavigation: false)
      case .files:
        LargeFileReviewView(model: workspace.storage.overview, monitor: workspace.monitor,
          onBrowseFolders: { workspace.open(.browse) })
      case .recovery:
        AppRecoveryView(memory: workspace.memory, model: workspace.recovery)
      case .memory:
        MemoryControlView(monitor: workspace.monitor, model: workspace.memory,
          processes: workspace.processes)
      case .projects:
        WorkspaceProjectsView(processes: workspace.processes, controller: workspace.projects)
      case .setup:
        CleanupSetupView(workspace: workspace)
      }
    }
  }

  @ViewBuilder private var welcome: some View {
    if exporting {
      welcomeContent.frame(maxHeight: .infinity, alignment: .top)
    } else {
      ScrollView { welcomeContent }.scrollIndicators(.hidden)
    }
  }

  private var welcomeContent: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        VStack(alignment: .leading, spacing: 5) {
          Text("Make space. Keep what matters.").font(.system(size: 17, weight: .semibold))
          Text("Scan your Mac, review the results, and choose what to remove.")
            .font(.system(size: 13)).foregroundStyle(BlitzUI.secondaryText)
        }
        Spacer()
        Button("Review cleanup", systemImage: "magnifyingglass") { workspace.open(.cleanup) }
          .blitzButton(.accent)
      }.padding(.vertical, 8)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 3), spacing: 18) {
        feature(.cleanup, title: "Caches & developer files",
          detail: "Old caches, diagnostic reports, dependencies, build output, simulators, Docker and merged worktrees.")
        feature(.browse, title: "Browse your storage",
          detail: "Explore folders and mounted drives with measured sizes, scan progress and Finder shortcuts.")
        feature(.inventory, title: "Storage inventory",
          detail: "See what uses space, identify app caches and select multiple caches to move to Trash.")
        feature(.files, title: "Large files & media",
          detail: "Review large files, check exact duplicates and export smaller media copies with FFmpeg.")
        feature(.recovery, title: "Revive your apps",
          detail: "Check app health and try recovery before choosing to quit or force quit an unresponsive app.")
        feature(.memory, title: "AI workers & projects",
          detail: "Inspect AI threads and app memory. Pause, resume or stop selected development processes.")
      }
      HStack(spacing: 7) {
        Image(systemName: "checkmark.shield").foregroundStyle(BlitzUI.mint)
        Text("Every removal is reviewed. Inventory selections use Trash; eligible automatic cleanup is permanent.")
          .font(.system(size: 12)).foregroundStyle(BlitzUI.secondaryText)
      }.padding(.top, 4)
    }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 24)
  }

  private func feature(_ section: CleanupSection, title: String, detail: String) -> some View {
    Button { workspace.open(section) } label: {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Image(systemName: section.symbol).font(.system(size: 16))
            .foregroundStyle(BlitzUI.mint).frame(width: 36, height: 36)
            .background(BlitzUI.mint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
          Spacer()
          Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(BlitzUI.tertiaryText)
        }
        Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
        Text(detail).font(.system(size: 13)).foregroundStyle(BlitzUI.secondaryText)
          .lineSpacing(4).frame(maxWidth: .infinity, alignment: .leading)
        Spacer(minLength: 0)
      }.padding(22).frame(minHeight: 190, alignment: .topLeading)
        .background(BlitzUI.panelBackground, in: RoundedRectangle(cornerRadius: 24))
        .contentShape(RoundedRectangle(cornerRadius: 24))
    }.buttonStyle(.plain)
  }
}

@MainActor
private struct CleanupSetupView: View {
  @ObservedObject var workspace: CleanupWorkspace
  @StateObject private var permissions = PermissionsModel()
  @State private var roots = DeveloperLocations.additionalProjectRoots

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        PermissionSetupSection(memory: workspace.memory, recovery: workspace.recovery,
          permissions: permissions)
        VStack(alignment: .leading, spacing: 14) {
          Text("Project folders").font(BlitzType.title)
          Text("Add project locations outside the usual developer folders to include them in cleanup scans.")
            .font(BlitzType.callout).foregroundStyle(BlitzUI.secondaryText)
          ForEach(roots, id: \.self) { root in
            HStack {
              Label(root, systemImage: "folder").font(BlitzType.body).textSelection(.enabled)
              Spacer()
              Button("Remove") {
                roots.removeAll { $0 == root }
                UserDefaults.standard.set(roots, forKey: "locations.projectRoots")
              }.blitzButton(.quiet)
            }
          }
          Button("Add folder…", systemImage: "plus") {
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            if panel.runModal() == .OK, let path = panel.url?.path, !roots.contains(path) {
              roots.append(path)
              UserDefaults.standard.set(roots, forKey: "locations.projectRoots")
            }
          }.blitzButton(.secondary)
        }.panelCard()
      }.padding(24)
    }.task { permissions.refresh() }
  }
}
