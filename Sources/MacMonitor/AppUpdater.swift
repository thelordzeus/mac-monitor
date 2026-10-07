import AppKit
import Combine
import Sparkle

/// One updater owns the update cycle for the dashboard and menu-bar panel.
/// Sparkle persists preferences and verifies our Ed25519 signatures itself.
@MainActor
final class AppUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
  @Published private(set) var isAvailable = false
  @Published private(set) var canCheckForUpdates = false
  @Published private(set) var automaticallyChecksForUpdates = false
  @Published private(set) var automaticallyDownloadsUpdates = false
  @Published private(set) var lastCheckDate: Date?
  @Published private(set) var unavailableReason = "Updates are available in the packaged app."

  private var controller: SPUStandardUpdaterController?
  private var subscriptions = Set<AnyCancellable>()

  func start() {
    guard controller == nil else { return }
    guard Bundle.main.bundleURL.pathExtension == "app",
      let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
      URL(string: feed)?.scheme == "https",
      let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
      Data(base64Encoded: key)?.count == 32
    else { return }

    let controller = SPUStandardUpdaterController(
      startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    self.controller = controller
    isAvailable = true
    let updater = controller.updater
    updater.publisher(for: \.canCheckForUpdates)
      .receive(on: RunLoop.main).sink { [weak self] value in
        self?.canCheckForUpdates = value
        self?.lastCheckDate = updater.lastUpdateCheckDate
      }.store(in: &subscriptions)
    updater.publisher(for: \.automaticallyChecksForUpdates)
      .receive(on: RunLoop.main).sink { [weak self] in
        self?.automaticallyChecksForUpdates = $0
      }.store(in: &subscriptions)
    updater.publisher(for: \.automaticallyDownloadsUpdates)
      .receive(on: RunLoop.main).sink { [weak self] in
        self?.automaticallyDownloadsUpdates = $0
      }.store(in: &subscriptions)
    lastCheckDate = updater.lastUpdateCheckDate
    // Initial behavior comes from Info.plist, preserving the user's saved choices.
    controller.startUpdater()
  }

  func checkForUpdates() {
    guard canCheckForUpdates else { return }
    NSApp.activate(ignoringOtherApps: true)
    controller?.checkForUpdates(nil)
  }

  func setAutomaticChecks(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
  }

  func setAutomaticDownloads(_ enabled: Bool) {
    controller?.updater.automaticallyDownloadsUpdates = enabled
  }

  nonisolated func updater(
    _ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?
  ) {
    Task { @MainActor [weak self] in
      self?.lastCheckDate = self?.controller?.updater.lastUpdateCheckDate
    }
  }
}
