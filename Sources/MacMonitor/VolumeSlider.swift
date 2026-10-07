import SwiftUI

struct VolumeSlider: View {
  @Binding var value: Double
  var enabled = true
  var body: some View {
    GeometryReader { geometry in
      let width = max(1, geometry.size.width - 14)
      let position = CGFloat(min(1, max(0, value))) * width
      ZStack(alignment: .leading) {
        Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
        Capsule().fill(MonitorTab.sound.color.opacity(enabled ? 1 : 0.35)).frame(
          width: position + 7, height: 4)
        Circle().fill(.white.opacity(enabled ? 1 : 0.35)).frame(width: 14, height: 14)
          .shadow(color: .black.opacity(0.2), radius: 1, y: 1).offset(x: position)
      }.frame(height: 24).contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { event in
            if enabled { value = min(1, max(0, Double((event.location.x - 7) / width))) }
          })
    }.frame(height: 24)
      .accessibilityElement().accessibilityLabel("Volume")
      .accessibilityValue(enabled ? Format.percent(value * 100) : "Hardware controlled")
      .accessibilityAdjustableAction { direction in
        if enabled {
          switch direction {
          case .increment: value = min(1, value + 0.05)
          case .decrement: value = max(0, value - 0.05)
          @unknown default: break
          }
        }
      }
  }
}
