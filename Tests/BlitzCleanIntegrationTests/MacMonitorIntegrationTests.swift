import Foundation
import Testing
@testable import BlitzCleanIntegration

struct MacMonitorIntegrationTests {
  @Test @MainActor func cleanupUsesTheHostCollectorsValues() {
    let monitor = SystemMonitor(externallyManaged: true)
    #expect(monitor.snapshot.diskTotal == 0)
    let metrics = CleanupMetrics(diskAvailable: 400_000_000_000, diskTotal: 1_000_000_000_000,
      ramAvailable: 8_589_934_592, ramTotal: 34_359_738_368, cpuPercent: 42,
      pressure: "Elevated", date: Date(timeIntervalSince1970: 100))
    monitor.applyExternal(metrics.snapshot)
    monitor.refresh() // Must not replace host readings with a competing collector.
    #expect(monitor.snapshot.diskAvailable == 400_000_000_000)
    #expect(monitor.snapshot.ramUsed == 25_769_803_776)
    #expect(monitor.snapshot.cpuUsage == 0.42)
    #expect(monitor.snapshot.memoryPressure == .warning)
    #expect(monitor.snapshot.updatedAt == metrics.date)
  }

  @Test func invalidValuesCannotBecomeBogusUsage() {
    let metrics = CleanupMetrics(diskAvailable: -.infinity, diskTotal: .nan,
      ramAvailable: -1, ramTotal: .infinity, cpuPercent: .nan,
      pressure: "Unavailable", date: .now)
    #expect(metrics.snapshot.diskAvailable == 0)
    #expect(metrics.snapshot.ramTotal == 0)
    #expect(metrics.snapshot.cpuUsage == nil)
    #expect(metrics.snapshot.memoryPressure == .unknown)
  }

  @Test func integrationProtectsTheHostAndIsolatesSavedData() {
    #expect(AppBrand.bundleIdentifier == "local.macmonitor.app")
    #expect(AppData.directory.path.hasSuffix("/MacMonitor/Cleanup"))
    #expect(!AppData.legacyDirectory.path.hasSuffix("/FreeSpace"))
  }
}
