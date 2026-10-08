import SwiftUI

struct MenuMetricDetail: View {
  @ObservedObject var store: MonitorStore
  let tab: MonitorTab
  var open: () -> Void
  var body: some View {
    let summary = Summary.make(tab, store: store)
    VStack(alignment: .leading, spacing: 16) {
      Label(tab.rawValue, systemImage: tab.symbol).font(.system(size: 17, weight: .semibold))
        .foregroundStyle(tab.color)
      Text(summary.caption).foregroundStyle(Color.muted)
      HStack(alignment: .firstTextBaseline) {
        Text(summary.value).font(.system(size: 42, weight: .semibold, design: .rounded))
        Text(summary.unit).foregroundStyle(Color.muted)
      }
      HistoryChart(samples: store.liveSamples, tab: tab).frame(height: 90)
      ForEach(Array(summary.facts.enumerated()), id: \.offset) { _, fact in
        HStack {
          Text(fact.0).foregroundStyle(Color.muted)
          Spacer()
          Text(fact.1).monospacedDigit()
        }
      }
      Button("Open \(tab.rawValue)") {
        store.selectedTab = tab
        open()
      }.buttonStyle(.plain).foregroundStyle(tab.color)
    }.font(.system(size: 13))
  }
}
struct FloatingDashboard: View {
  @ObservedObject var store: MonitorStore
  var open: () -> Void
  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Label("Mac Pulse", systemImage: "waveform.path.ecg").font(
          .system(size: 13, weight: .semibold))
        Spacer()
        Button {
          store.floatingDashboard = false
        } label: {
          Image(systemName: "xmark")
        }.buttonStyle(.plain).help("Hide floating dashboard")
      }
      LazyVGrid(
        columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10
      ) {
        ForEach([MonitorTab.cpu, .memory, .disk, .network, .gpu, .battery]) { tab in
          let summary = Summary.make(tab, store: store)
          Button {
            store.selectedTab = tab
            open()
          } label: {
            VStack(alignment: .leading, spacing: 6) {
              Label(tab.rawValue, systemImage: tab.symbol).font(.system(size: 10)).foregroundStyle(
                tab.color)
              Text(summary.value + " " + summary.unit).font(.system(size: 14, weight: .semibold))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
              if tab == .battery && !store.snapshot.battery.present {
                Text("No internal battery").font(.system(size: 8)).foregroundStyle(Color.muted)
                  .lineLimit(1).frame(height: 18)
              } else if tab == .gpu && store.snapshot.gpu == nil {
                Text("Not reported").font(.system(size: 9)).foregroundStyle(Color.muted)
                  .frame(height: 18)
              } else {
                HistoryChart(samples: store.liveSamples, tab: tab, bars: true).frame(height: 18)
              }
            }.padding(9).frame(maxWidth: .infinity, alignment: .leading).background(
              Color.surface, in: RoundedRectangle(cornerRadius: 10))
          }.buttonStyle(.plain)
        }
      }
      HStack {
        Text(store.paused ? "Paused" : "Live · drag to move").font(.system(size: 10))
          .foregroundStyle(Color.muted)
        Spacer()
        Button("Open Dashboard", action: open).buttonStyle(.plain).font(.system(size: 11))
      }
    }.padding(15).frame(width: 340, height: 230).background(
      Color.window, in: RoundedRectangle(cornerRadius: 16)
    ).preferredColorScheme(.dark)
  }
}
