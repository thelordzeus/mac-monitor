import AppKit
import SwiftUI

struct CPUControlView: View {
  @ObservedObject var monitor: SystemMonitor
  @AppStorage("history.cpuSeconds") private var seconds = 86_400.0

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 18) {
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(monitor.snapshot.cpuUsage.map(PercentText.make) ?? "—")
              .font(PulseUI.valueFont).monospacedDigit()
            Text("\(ProcessInfo.processInfo.activeProcessorCount) cores")
              .font(PulseType.body).foregroundStyle(PulseUI.secondaryText)
            Spacer()
            HistoryRangePicker(seconds: $seconds)
          }
          ResourcePlot(
            samples: monitor.resourceSamples, kind: .cpu, color: PulseUI.mint, seconds: seconds
          )
          .frame(height: 130)
          .help("Total CPU usage across all cores, from 0 to 100%")
          if monitor.snapshot.thermalStatus != .nominal {
            PulseStatusBadge(
              title: "Thermals: \(monitor.snapshot.thermalStatus.title)", tone: .warning)
          }
        }.panelCard(padding: 20)
        let processes = monitor.topCPUProcesses
        PulseSectionHeader(title: "Processes", count: nil) {
          Button("Open Activity Monitor") {
            NSWorkspace.shared.open(
              URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
          }.pulseButton(.quiet).controlSize(.small)
        }
        LazyVStack(spacing: 0) {
          if processes.isEmpty {
            PulseEmptyRow(text: "Measuring CPU activity…", isLoading: true)
          }
          ForEach(processes) { process in
            HStack(spacing: 12) {
              ApplicationIcon(source: .process(process.id), size: 28, fallback: "terminal")
              Text(process.name).font(PulseType.rowTitle).lineLimit(1)
              Spacer()
              PulseTrailingValue(
                value: process.percent.formatted(.number.precision(.fractionLength(1))) + "%",
                detail: nil)
            }.pulseRow()
              .help("PID \(process.id)")
            if process.id != processes.last?.id { PulseRowDivider(leading: 56) }
          }
        }.pulseTable()
        Text("100% per process equals one core. macOS restricts access to some processes.")
          .font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
      }.padding(PulseUI.pagePadding)
    }
  }
}
