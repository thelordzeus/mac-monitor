import SwiftUI

struct HistoryChart: View {
  var samples: [Sample]
  var tab: MonitorTab
  var maximum: Double? = nil
  var bars = false
  @State private var hoverX: CGFloat?
  var values: [Double] { samples.map { $0.value(tab) } }
  var body: some View {
    GeometryReader { geometry in
      let size = geometry.size
      let maxValue = max(1, maximum ?? ((values.max() ?? 1) * 1.12))
      let times = samples.map(\.timestamp)
      let start = times.first ?? 0
      let span = max(1, (times.last ?? 0) - start)
      Canvas { context, canvas in
        if !bars {
          for i in 0..<4 {
            let y = canvas.height * CGFloat(i) / 3
            var line = Path()
            line.move(to: CGPoint(x: 0, y: y))
            line.addLine(to: CGPoint(x: canvas.width, y: y))
            context.stroke(line, with: .color(.white.opacity(0.09)), lineWidth: 1)
          }
        }
        guard !values.isEmpty else { return }
        if bars {
          let count = min(50, values.count)
          let stride = max(1, values.count / count)
          let points = values.enumerated().filter { $0.offset % stride == 0 }.map(\.element).suffix(
            50)
          let width = canvas.width / CGFloat(max(1, points.count))
          for (i, v) in points.enumerated() {
            let height = max(2, min(canvas.height, canvas.height * CGFloat(v / maxValue)))
            let rect = CGRect(
              x: CGFloat(i) * width + 1.2, y: canvas.height - height, width: max(2, width - 2.4),
              height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(tab.color))
          }
        } else {
          var line = Path()
          for (i, v) in values.enumerated() {
            let x = canvas.width * CGFloat((times[i] - start) / span)
            let y = canvas.height * (1 - CGFloat(min(max(v / maxValue, 0), 1)))
            if i == 0 {
              line.move(to: CGPoint(x: x, y: y))
            } else {
              line.addLine(to: CGPoint(x: x, y: y))
            }
          }
          if values.count == 1 {
            context.fill(
              Path(
                ellipseIn: CGRect(
                  x: 0, y: canvas.height * (1 - CGFloat(values[0] / maxValue)) - 2, width: 4,
                  height: 4)), with: .color(tab.color))
          } else {
            var area = line
            area.addLine(to: CGPoint(x: canvas.width, y: canvas.height))
            area.addLine(to: CGPoint(x: 0, y: canvas.height))
            area.closeSubpath()
            context.fill(
              area,
              with: .linearGradient(
                Gradient(colors: [tab.color.opacity(0.38), tab.color.opacity(0.015)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: canvas.height)))
            context.stroke(
              line, with: .color(tab.color),
              style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
          }
          if let hoverX, let index = nearest(hoverX, width: canvas.width), index < values.count {
            let x = canvas.width * CGFloat((times[index] - start) / span)
            let y = canvas.height * (1 - CGFloat(min(max(values[index] / maxValue, 0), 1)))
            var cursor = Path()
            cursor.move(to: CGPoint(x: x, y: 0))
            cursor.addLine(to: CGPoint(x: x, y: canvas.height))
            context.stroke(
              cursor, with: .color(.white.opacity(0.25)),
              style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            context.fill(
              Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)),
              with: .color(tab.color))
          }
        }
      }
      .onContinuousHover { phase in
        switch phase {
        case .active(let point): hoverX = point.x
        case .ended: hoverX = nil
        }
      }
      if samples.isEmpty {
        Text("History appears as your Mac is monitored").font(.system(size: 12)).foregroundStyle(
          Color.muted
        ).frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if !bars, let x = hoverX, let index = nearest(x, width: size.width), index < samples.count {
        VStack(alignment: .leading, spacing: 3) {
          Text(display(values[index])).font(.system(size: 12, weight: .semibold)).foregroundStyle(
            .white)
          Text(
            Date(timeIntervalSince1970: samples[index].timestamp).formatted(
              date: .abbreviated, time: .standard)
          ).font(.system(size: 10)).foregroundStyle(Color.muted)
        }.padding(8).background(Color.window, in: RoundedRectangle(cornerRadius: 8)).position(
          x: min(max(x, 85), size.width - 85), y: 22)
      }
    }
    .accessibilityLabel("\(tab.rawValue) history chart, \(samples.count) samples")
  }
  private func nearest(_ x: CGFloat, width: CGFloat) -> Int? {
    guard !samples.isEmpty else { return nil }
    return min(samples.count - 1, max(0, Int(x / max(1, width) * CGFloat(samples.count - 1))))
  }
  private func display(_ value: Double) -> String {
    switch tab {
    case .memory: return Format.memory(value)
    case .disk, .network: return Format.rate(value)
    default: return Format.percent(value, precise: true)
    }
  }
}
struct RingSlice {
  var name: String
  var value: Double
  var color: Color
  var icon: NSImage? = nil
}
struct BreakdownCard: View {
  var title: String
  var tab: MonitorTab
  var center: String
  var subtitle: String
  var slices: [RingSlice]
  var bytes = true
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      LabelBadge(
        title: title, symbol: tab == .battery ? "bolt" : "square.grid.2x2", color: tab.color)
      HStack(spacing: 20) {
        ZStack {
          Circle().stroke(Color.white.opacity(0.04), lineWidth: 14)
          ForEach(Array(slices.enumerated()), id: \.offset) { i, slice in
            Circle().trim(from: start(i), to: max(start(i), start(i + 1) - 0.004)).stroke(
              slice.color, style: StrokeStyle(lineWidth: 14, lineCap: .butt)
            ).rotationEffect(.degrees(-90))
          }
          VStack(spacing: 2) {
            Text(center).font(.system(size: 18, weight: .semibold)).minimumScaleFactor(0.7)
              .lineLimit(1)
            Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.muted)
          }.padding(8)
        }.frame(width: 96, height: 96)
        VStack(spacing: 9) {
          ForEach(Array(slices.enumerated()), id: \.offset) { _, slice in
            HStack(spacing: 6) {
              Circle().fill(slice.color).frame(width: 6, height: 6)
              if let icon = slice.icon {
                Image(nsImage: icon).resizable().frame(width: 14, height: 14)
              }
              Text(slice.name).font(.system(size: 12)).lineLimit(1)
              Spacer(minLength: 0)
              Text(bytes ? Format.memory(slice.value) : Format.watts(slice.value)).font(
                .system(size: 12)
              ).foregroundStyle(Color.muted).lineLimit(1).minimumScaleFactor(0.7)
            }
          }
        }.frame(maxWidth: .infinity)
      }
    }.padding(20).frame(maxWidth: .infinity, alignment: .leading).frame(height: 202).background(
      Color.surface, in: RoundedRectangle(cornerRadius: 22))
  }
  private func start(_ index: Int) -> Double {
    let total = max(1, slices.reduce(0) { $0 + $1.value })
    return slices.prefix(index).reduce(0) { $0 + $1.value } / total
  }
}
struct LabelBadge: View {
  var title: String
  var symbol: String
  var color: Color
  var coloredTitle = true
  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: symbol).font(.system(size: 13, weight: .medium)).foregroundStyle(color)
        .frame(width: 27, height: 27).background(
          color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
      Text(title).font(.system(size: 14, weight: coloredTitle ? .medium : .regular))
        .foregroundStyle(coloredTitle ? color : .muted)
    }
  }
}
struct GaugeBar: View {
  var value: Double
  var maximum: Double
  var color: Color
  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(color.opacity(0.17))
        Capsule().fill(color).frame(
          width: max(0, geo.size.width * min(1, max(0, value / max(1, maximum)))))
      }
    }.frame(height: 5)
  }
}
struct StatusPill: View {
  var title: String
  var color: Color = .green
  var symbol: String? = nil
  var body: some View {
    HStack(spacing: 4) {
      if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
      Text(title).font(.system(size: 12, weight: .medium))
    }
    .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 4).background(
      color.opacity(0.13), in: Capsule())
  }
}
struct AppIcon: View {
  var image: NSImage?
  var size: CGFloat = 25
  var body: some View {
    Group {
      if let image {
        Image(nsImage: image).resizable().interpolation(.high)
      } else {
        Image(systemName: "terminal").resizable().scaledToFit().foregroundStyle(Color.muted)
          .padding(3)
      }
    }.frame(width: size, height: size)
  }
}
