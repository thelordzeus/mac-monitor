import SwiftUI

struct CleanupReceiptsView: View {
  @ObservedObject var model: CleanupOverviewModel
  @State private var pending: (CleanupWin, TrashRecord)?
  @State private var status: String?
  @State private var restoring = false
  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 18) {
        HStack {
          VStack(alignment: .leading, spacing: 5) {
            Text("Cleanup receipts").font(PulseType.section)
            Text("Exact paths, measured free-space changes and tracked Trash items.")
              .foregroundStyle(PulseUI.secondaryText)
          }
          Spacer()
          Button("Refresh") { model.synchronize() }.pulseButton(.secondary)
        }
        if let status { PulseStatusLine(text: status, tone: .muted) }
        if let error = model.historyError { PulseStatusLine(text: error, tone: .warning) }
        if model.ledger.wins.isEmpty {
          Text(
            "Cleanup actions will appear here. Older receipts without Trash tracking remain view-only."
          ).foregroundStyle(PulseUI.secondaryText).padding(.vertical, 30)
        }
        ForEach(model.ledger.wins) { win in
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(win.title).font(PulseType.rowTitle)
              Spacer()
              Text(win.date.formatted(date: .abbreviated, time: .shortened)).font(PulseType.caption)
                .foregroundStyle(PulseUI.secondaryText)
            }
            HStack(spacing: 24) {
              Text("Selected size: \(win.bytes.map(ByteText.full) ?? "Not recorded")")
              Text("Free-space change: \(win.measuredGain.map(ByteText.full) ?? "Not measured")")
            }.font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
            ForEach(win.paths, id: \.self) { path in
              Text(path).font(PulseType.caption).textSelection(.enabled).foregroundStyle(
                PulseUI.secondaryText)
            }
            if let records = win.recovery, !records.isEmpty {
              ForEach(records) { receipt in
                HStack {
                  Text(URL(fileURLWithPath: receipt.originalPath).lastPathComponent).lineLimit(1)
                  Spacer()
                  if receipt.restoredAt != nil {
                    Text("Restored").foregroundStyle(PulseUI.mint)
                  } else {
                    Button("Restore…") { pending = (win, receipt) }.pulseButton(.secondary)
                      .disabled(restoring)
                    Button("Show in Trash") { Finder.reveal(receipt.trashPath) }.pulseButton(.quiet)
                  }
                }
              }
              Text(
                "Items in Trash still occupy disk space. Restore checks identity and never replaces an existing file."
              ).font(PulseType.caption).foregroundStyle(PulseUI.tertiaryText)
            } else {
              Text("No tracked restore available for this receipt.").font(PulseType.caption)
                .foregroundStyle(PulseUI.tertiaryText)
            }
          }.padding(20).background(PulseUI.panelBackground, in: RoundedRectangle(cornerRadius: 18))
        }
      }.padding(PulseUI.pagePadding)
    }.task { model.synchronize() }
      .safeAreaInset(edge: .bottom) {
        if let (win, receipt) = pending {
          PulseConfirmation(
            title: "Restore this item?",
            message: receipt.originalPath
              + "\n\nThe original folder must still exist and the destination must be empty.",
            confirmTitle: "Restore",
            onConfirm: {
              pending = nil
              restoring = true
              Task {
                do {
                  try await Task.detached(priority: .utility) { try TrashRecovery.restore(receipt) }
                    .value
                  var updated = win
                  if let index = updated.recovery?.firstIndex(where: { $0.id == receipt.id }) {
                    updated.recovery?[index].restoredAt = .now
                  }
                  model.record(updated)
                  status = "Restored to \(receipt.originalPath)"
                } catch { status = error.localizedDescription }
                restoring = false
              }
            }, onCancel: { pending = nil })
        }
      }
  }
}
