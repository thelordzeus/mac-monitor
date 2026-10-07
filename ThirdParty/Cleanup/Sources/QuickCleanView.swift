import SwiftUI

struct QuickCleanView: View {
  @ObservedObject var model: QuickCleanModel
  @ObservedObject var history: CleanupOverviewModel
  @State private var pendingReview: CacheCleanupReview?

  private struct CacheCleanupReview: Identifiable {
    let id = UUID()
    let items: [CacheCandidate]
  }

  var body: some View {
    let selectedItems = model.selectedItems
    let isLocked = model.isScanning || model.isCleaning
    return VStack(spacing: 0) {
      if model.isScanning && model.candidates.isEmpty {
        PulseEmptyRow(
          text: "Checking caches, diagnostic reports, and running tools…", isLoading: true)
      } else if model.candidates.isEmpty {
        PulseEmptyRow(text: "No eligible files found in the checked locations", isLoading: false)
      }
      if let status = model.status {
        PulseStatusLine(text: status, tone: .working).padding(.horizontal, 16)
          .padding(.vertical, 10)
      }
      if !model.candidates.isEmpty {
        HStack {
          Toggle(
            "Select all",
            isOn: Binding(
              get: { selectedItems.count == model.candidates.count },
              set: { model.selected = $0 ? Set(model.candidates.map(\.path)) : [] }
            )
          ).toggleStyle(PulseCheckboxStyle()).font(PulseType.label).disabled(isLocked)
          Spacer()
        }.padding(.horizontal, 16).padding(.vertical, 4)
        PulseRowDivider(leading: 0)
        LazyVStack(spacing: 0) {
          ForEach(model.candidates) { item in
            row((item: item, isLocked: isLocked))
            if item.id != model.candidates.last?.id { PulseRowDivider(leading: 56) }
          }
        }
      }
      if !model.notes.isEmpty {
        PulseRowDivider(leading: 0)
        VStack(alignment: .leading, spacing: 4) {
          Text("Kept or skipped · \(model.notes.count)").font(PulseType.captionEmphasis)
            .foregroundStyle(PulseUI.secondaryText)
          ForEach(Array(model.notes.enumerated()), id: \.offset) { note in
            Text(note.element).font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }.padding(16)
      }
      if !model.candidates.isEmpty || model.isCleaning {
        StorageActionBar(
          summary: "\(selectedItems.count) selected · \(ByteText.full(model.selectedBytes))",
          progress: model.isCleaning ? "Deleting selected files…" : nil, message: nil,
          actionTitle: "Review cleanup…", emphasis: .secondary,
          isDisabled: selectedItems.isEmpty || isLocked,
          action: { pendingReview = CacheCleanupReview(items: selectedItems) }
        ).padding(.horizontal, 16)
      }
      if let review = pendingReview {
        PulseConfirmation(
          title: "Delete \(review.items.count) selected items?",
          message:
            "\(ByteText.full(review.items.reduce(0) { $0 + $1.tree.bytes })) will be checked for cleanup. This permanently removes the selected files. Caches rebuild; diagnostic reports cannot be recovered. Future downloads and builds can take longer.\n\n"
            + review.items.map { $0.rule.title + " / " + $0.displayName }.joined(separator: "\n"),
          confirmTitle: "Delete selected files",
          onConfirm: {
            model.selected = Set(review.items.map(\.path))
            pendingReview = nil
            model.clean(history: history)
          }, onCancel: { pendingReview = nil })
      }
    }
    .task { if model.scannedAt == nil { model.scan() } }
  }

  private func row(_ input: (item: CacheCandidate, isLocked: Bool)) -> some View {
    let item = input.item
    return HStack(spacing: 12) {
      Toggle(
        "Select \(item.displayName)",
        isOn: Binding(
          get: { model.selected.contains(item.path) },
          set: {
            if $0 { model.selected.insert(item.path) } else { model.selected.remove(item.path) }
          })
      ).toggleStyle(PulseCheckboxStyle(showsLabel: false)).disabled(input.isLocked)
      ApplicationIcon(source: .file(item.path), size: 28, fallback: "folder")
      VStack(alignment: .leading, spacing: 3) {
        Text(item.displayName).font(PulseType.rowTitle).lineLimit(1).truncationMode(.middle)
        Text("\(item.rule.title) · unchanged for \(item.rule.kind.minimumAgeDays)+ days")
          .font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
      }.frame(maxWidth: .infinity, alignment: .leading).help(item.rule.recipe + "\n" + item.path)
      PulseTrailingValue(value: ByteText.full(item.tree.bytes), detail: nil)
      Button("Show in Finder") { Finder.reveal(item.path) }.pulseButton(.quiet)
        .controlSize(.small)
    }.pulseRow()
  }
}
