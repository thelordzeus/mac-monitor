import SwiftUI
@testable import BlitzCleanIntegration

@MainActor
enum AuditRenderFixture {
  struct Input {
    let model: QuickCleanModel
    let summary: OverviewCleanupSummary
    let isScanning: Bool
  }

  static var complete: AuditProgress {
    var progress = AuditProgress()
    progress.begin(at: .now)
    for check in AuditCheck.allCases {
      progress.finish(.init(check: check, warnings: [], date: .now))
    }
    return progress
  }

  static func presentation(_ findings: AuditFindings) -> AuditPresentation {
    .init(
      progress: findings.progress, recommendations: findings.recommendations, cleanupResult: nil,
      isCleaning: false, cleaningCompleted: 0, cleaningTotal: 0, isMutating: false,
      historyError: nil)
  }

  static func card(_ input: Input) -> some View {
    var progress = AuditProgress()
    progress.begin(at: .now)
    if !input.isScanning {
      for check in AuditCheck.allCases {
        let warnings =
          check == .docker && input.summary.dockerUnavailable
          ? ["Docker could not be checked."] : []
        progress.finish(.init(check: check, warnings: warnings, date: .now))
      }
    }
    let findings = AuditFindings(
      progress: progress, cleanup: input.summary, quickBytes: input.model.quickBytes,
      canClean: input.model.canClean, pressure: .checking, detachedCount: 0, detachedBytes: 0,
      recoveryCount: 0)
    return OverviewCleanCard(
      presentation: .init(
        progress: progress, recommendations: findings.recommendations,
        cleanupResult: input.model.result.map {
          .init(outcome: $0, notes: input.model.notes, date: .now)
        },
        isCleaning: input.model.isCleaning, cleaningCompleted: input.model.completed,
        cleaningTotal: input.model.total, isMutating: input.model.isBusy, historyError: nil),
      vitals: vitals, onCheck: {}, onAction: { _ in }, onOpen: { _ in })
  }

  static var vitals: [MacVital] {
    let gib: UInt64 = 1 << 30
    let snapshot = SystemSnapshot(
      .init(
        diskAvailable: 26 * gib, diskTotal: 460 * gib, ramAvailable: 10 * gib,
        ramTotal: 36 * gib, memoryPressure: .normal, cpuUsage: 0.22, thermalStatus: .nominal,
        updatedAt: .now))
    return MacVital.all(.init(snapshot: snapshot, memoryDisplay: .available, memoryTone: .good))
  }
}
