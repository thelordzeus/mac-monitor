import AppKit
import SwiftUI

struct MemoryGuardControls: View {
  @ObservedObject var model: MemoryRescueModel

  var body: some View {
    let anyAlert = model.alertsEnabled || model.diskAlertsEnabled
    VStack(alignment: .leading, spacing: 9) {
      Toggle(
        "Memory alerts",
        isOn: Binding(
          get: { model.alertsEnabled }, set: { model.setAlertsEnabled($0) }
        ))
      Toggle(
        "Disk alerts · \(DiskSpacePolicy.reserveLabel) reserve",
        isOn: Binding(
          get: { model.diskAlertsEnabled }, set: { model.setDiskAlertsEnabled($0) }
        ))
      Text(anyAlert ? model.notificationStatus : "Alerts paused; monitoring continues")
        .font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
      HStack {
        Button("Send test alert") { Task { await model.testNotification() } }
          .disabled(!anyAlert)
        Button("Notification settings…") { SystemSettingsPane.notifications.open() }
      }.pulseButton(.quiet).controlSize(.small).padding(.top, 4)
    }
    .toggleStyle(PulseSwitchStyle()).font(PulseType.callout)
    .panelCard()
  }
}

extension MemoryRisk {
  var tone: MetricTone {
    switch self {
    case .normal: .good
    case .growing, .warning: .warning
    case .critical: .critical
    }
  }
}

extension MemoryPressureLevel {
  var tone: MetricTone {
    switch self {
    case .normal: .good
    case .warning: .warning
    case .critical: .critical
    case .unknown: .neutral
    }
  }
}
