import SwiftUI

struct AppLeftoversView: View {
  @ObservedObject var model: AppLeftoverModel
  let history: CleanupOverviewModel
  let finished: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var confirming = false
  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("Review app files").font(.system(size: 23, weight: .semibold))
        Spacer()
        Button("Done") { dismiss() }.disabled(model.busy)
      }
      if model.busy {
        ProgressView()
        Text("Checking app files…").foregroundStyle(PulseUI.secondaryText)
      }
      if let status = model.status {
        Text(status).foregroundStyle(PulseUI.secondaryText).textSelection(.enabled)
      }
      if let review = model.review {
        Text(review.name).font(.system(size: 18, weight: .semibold))
        Text(
          "Only files matched to the app's bundle identifier are listed. Shared containers and unrelated folders are kept. Support data and preferences can contain personal app data."
        )
        .font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
        ScrollView {
          VStack(alignment: .leading, spacing: 12) {
            ForEach(review.candidates) { candidate in
              HStack(alignment: .top, spacing: 12) {
                Toggle(
                  "Select \(candidate.title)",
                  isOn: Binding(
                    get: { model.selected.contains(candidate.path) },
                    set: {
                      if $0 {
                        model.selected.insert(candidate.path)
                      } else {
                        model.selected.remove(candidate.path)
                      }
                    })
                ).labelsHidden().disabled(model.busy || confirming)
                VStack(alignment: .leading, spacing: 5) {
                  Text(candidate.title).font(PulseType.rowTitle)
                  Text(candidate.path).font(PulseType.caption).foregroundStyle(
                    PulseUI.secondaryText
                  ).textSelection(.enabled)
                  Text(candidate.detail).font(PulseType.caption).foregroundStyle(
                    PulseUI.tertiaryText)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(ByteText.full(candidate.bytes)).monospacedDigit()
              }.padding(14).background(
                PulseUI.panelBackground, in: RoundedRectangle(cornerRadius: 12))
            }
            ForEach(review.notes, id: \.self) {
              Text($0).font(PulseType.caption).foregroundStyle(PulseUI.warning)
            }
          }
        }
        if confirming {
          PulseConfirmation(
            title: "Move \(model.selected.count) selected items to Trash?",
            message: review.candidates.filter { model.selected.contains($0.path) }.map(\.path)
              .joined(separator: "\n")
              + "\n\nQuit the app first. Selected support data may include profiles and settings. Restore is available while the tracked items remain in Trash.",
            confirmTitle: "Move to Trash",
            onConfirm: {
              confirming = false
              model.remove(history: history, finished: finished)
            }, onCancel: { confirming = false })
        } else {
          Button("Move selected to Trash…", role: .destructive) { confirming = true }.pulseButton(
            .accent
          ).disabled(model.selected.isEmpty || model.busy)
        }
      }
    }.padding(24).frame(width: 780, height: 600).background(PulseUI.canvasBackground)
      .preferredColorScheme(.dark)
  }
}
