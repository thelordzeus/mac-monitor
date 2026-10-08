import PulseCore
import SwiftUI

struct AlertRulesView: View {
  @ObservedObject var store: MonitorStore
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Toggle("Send macOS notifications", isOn: $store.notifications)
      Text(
        "Findings still appear in Activity alerts when notifications are disabled. Each rule has a 30-minute repeat cooldown."
      )
      .font(.system(size: 12)).foregroundStyle(Color.muted)
      Toggle("Quiet hours for notifications", isOn: $store.quietHours.enabled)
      if store.quietHours.enabled {
        HStack {
          Picker("From", selection: $store.quietHours.startHour) {
            ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
          }
          Picker("Until", selection: $store.quietHours.endHour) {
            ForEach(0..<24) { Text(String(format: "%02d:00", $0)).tag($0) }
          }
        }
        Text("Uses local time. Equal start/end hours silence notifications all day.").font(
          .system(size: 11)
        ).foregroundStyle(Color.muted)
      }
      Divider()
      ForEach($store.alertRules) { $rule in
        VStack(alignment: .leading, spacing: 10) {
          HStack {
            Toggle("Enabled", isOn: $rule.enabled).labelsHidden()
            Picker("Metric", selection: $rule.metric) {
              ForEach(AlertMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .onChange(of: rule.metric) { _, metric in
              rule.threshold = metric.defaultThreshold
              rule.seconds = metric == .memoryGrowth ? 0 : 60
              rule.appID = nil
            }
            Button {
              store.alertRules.removeAll { $0.id == rule.id }
            } label: {
              Image(systemName: "minus.circle")
            }.help("Remove this alert rule")
          }
          if rule.metric == .pressure {
            Picker("At least", selection: $rule.threshold) {
              Text("Elevated pressure").tag(1.0)
              Text("Critical pressure").tag(2.0)
            }
          } else {
            HStack {
              Text(rule.metric == .diskFree ? "Below" : "At least")
              TextField("Threshold", value: $rule.threshold, format: .number).textFieldStyle(
                .roundedBorder
              ).frame(width: 84)
                .onChange(of: rule.threshold) { _, value in
                  if !value.isFinite || value <= 0 { rule.threshold = rule.metric.defaultThreshold }
                }
              Text(rule.metric.unit).foregroundStyle(Color.muted).font(.system(size: 12))
            }
          }
          if rule.metric != .memoryGrowth {
            Stepper(
              "Observed for \(Int(rule.seconds)) seconds", value: $rule.seconds, in: 0...3600,
              step: 10)
          } else {
            Text("Growth compares ten-minute observations of the same app instance.").font(
              .system(size: 11)
            ).foregroundStyle(Color.muted)
          }
          if rule.metric.isAppMetric {
            Picker("Application", selection: $rule.appID) {
              Text("All apps").tag(Optional<String>.none)
              ForEach(store.snapshot.apps.filter { !$0.isSystem }) { app in
                Text(app.name).tag(Optional(app.id))
              }
              if let id = rule.appID, !store.snapshot.apps.contains(where: { $0.id == id }) {
                Text("Saved app · \(id)").tag(Optional(id))
              }
            }
          }
        }.padding(14).background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
      }
      HStack {
        Button("Add rule", systemImage: "plus") { store.alertRules.append(AlertRule(metric: .cpu)) }
          .disabled(store.alertRules.count >= 30)
        Spacer()
        Button("Restore default rules") { store.alertRules = AlertRule.defaults }
      }
      Text(
        "CPU thresholds use percent of the whole Mac. Unavailable sensors are skipped. Sleep, pause and restarted apps reset sustained-activity measurements."
      ).font(.system(size: 12)).foregroundStyle(Color.muted)
    }
  }
}
