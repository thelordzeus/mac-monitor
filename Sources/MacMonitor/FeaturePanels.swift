import AppKit
import PulseCore
import SwiftUI

@MainActor final class StorageGrowthModel: ObservableObject {
  @Published var roots: [String]
  @Published var selected: String {
    didSet { UserDefaults.standard.set(selected, forKey: "storageGrowthSelected") }
  }
  @Published var history: StorageHistory
  @Published var scanning = false
  @Published var status: String?
  @Published var comparisonID: UUID?
  private let file: URL
  private var worker: Task<Void, Never>?
  init() {
    let home = FileManager.default.homeDirectoryForCurrentUser
    file = home.appendingPathComponent("Library/Application Support/MacMonitor/storage-growth.json")
    let configuredRoots =
      UserDefaults.standard.stringArray(forKey: "storageGrowthRoots") ?? [
        home.appendingPathComponent("Library/Caches").path,
        home.appendingPathComponent("Downloads").path,
      ]
    roots = configuredRoots
    let savedSelection = UserDefaults.standard.string(forKey: "storageGrowthSelected") ?? ""
    selected =
      configuredRoots.contains(savedSelection) ? savedSelection : configuredRoots.first ?? ""
    if let data = try? Data(contentsOf: file),
      let saved = try? JSONDecoder().decode(StorageHistory.self, from: data)
    {
      history = saved
    } else {
      history = StorageHistory()
    }
  }
  var current: StorageSnapshot? { history.snapshots.first { $0.root == selected } }
  var previous: StorageSnapshot? {
    guard let current else { return nil }
    if let comparisonID {
      return history.snapshots.first {
        $0.id == comparisonID && $0.root == selected && $0.complete && $0.date < current.date
      }
    }
    return history.previous(to: current)
  }
  func addFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = true
    guard panel.runModal() == .OK else { return }
    for url in panel.urls {
      let path = url.resolvingSymlinksInPath().path
      if !roots.contains(path) { roots.append(path) }
      selected = path
    }
    UserDefaults.standard.set(roots, forKey: "storageGrowthRoots")
  }
  func removeFolder() {
    guard !scanning else { return }
    roots.removeAll { $0 == selected }
    selected = roots.first ?? ""
    UserDefaults.standard.set(roots, forKey: "storageGrowthRoots")
  }
  func scan() {
    guard !scanning, !selected.isEmpty else { return }
    scanning = true
    status = "Measuring allocated bytes…"
    comparisonID = nil
    let root = selected
    worker = Task {
      let task = Task.detached(priority: .utility) { StorageScanner.scan(root: root) }
      let scan = await withTaskCancellationHandler {
        await task.value
      } onCancel: {
        task.cancel()
      }
      history.record(scan)
      do {
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(history).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        status =
          scan.complete
          ? "Scan saved. Compare with an earlier complete scan."
          : "Partial scan: permission, cancellation or scan limits. Growth comparisons are unavailable for this scan."
      } catch {
        status = "Scan finished but history could not be saved: \(error.localizedDescription)"
      }
      scanning = false
      worker = nil
    }
  }
  func cancel() { worker?.cancel() }
}
@MainActor struct StorageGrowthView: View {
  @ObservedObject var model: StorageGrowthModel
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      featureHeader(
        "What filled my disk?",
        detail: "Compare allocated folder sizes over time. Scans stay on this Mac for 90 days.",
        symbol: "chart.pie", color: MonitorTab.disk.color)
      HStack {
        Picker("Tracked folder", selection: $model.selected) {
          ForEach(model.roots, id: \.self) { Text(shortPath($0)).tag($0) }
        }.frame(maxWidth: 500).disabled(model.scanning)
        Button("Add folder…") { model.addFolder() }.disabled(model.scanning)
        Button("Stop tracking") { model.removeFolder() }.disabled(
          model.scanning || model.selected.isEmpty)
        Spacer()
        if model.scanning {
          ProgressView().controlSize(.small)
          Button("Cancel scan") { model.cancel() }
        } else {
          Button("Scan folder", systemImage: "arrow.clockwise") { model.scan() }.disabled(
            model.selected.isEmpty)
        }
      }.onChange(of: model.selected) { _, _ in model.comparisonID = nil }
      if let text = model.status { Text(text).font(.system(size: 12)).foregroundStyle(Color.muted) }
      if let current = model.current {
        HStack(spacing: 18) {
          featureStat(
            current.complete ? "Allocated size" : "Measured minimum",
            Format.bytes(Double(current.bytes)), symbol: "internaldrive")
          featureStat(
            "Latest scan", current.date.formatted(date: .abbreviated, time: .shortened),
            symbol: "clock")
          featureStat(
            "Coverage", current.complete ? "Complete" : "Partial", symbol: "checkmark.shield")
        }
        Text("Storage map").font(.system(size: 18, weight: .semibold))
        GeometryReader { geo in
          let entries = Array(current.entries.filter { $0.bytes > 0 }.prefix(24))
          let other = current.bytes - entries.reduce(0) { $0 + $1.bytes }
          let map =
            entries + (other > 0 ? [StorageSize(path: "Other measured items", bytes: other)] : [])
          ZStack(alignment: .topLeading) {
            ForEach(
              Array(
                StorageMap.tiles(map, width: geo.size.width, height: geo.size.height).enumerated()),
              id: \.element.id
            ) { index, tile in
              Button {
                if tile.entry.path.hasPrefix("/") {
                  NSWorkspace.shared.activateFileViewerSelecting([
                    URL(fileURLWithPath: tile.entry.path)
                  ])
                }
              } label: {
                VStack(alignment: .leading, spacing: 4) {
                  Text(tile.entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                  Text(Format.bytes(Double(tile.entry.bytes))).font(.system(size: 11)).opacity(0.8)
                }.padding(10).frame(
                  width: max(0, tile.width - 4), height: max(0, tile.height - 4),
                  alignment: .topLeading
                )
                .background(
                  MonitorTab.disk.color.opacity(0.25 + Double(index % 4) * 0.10),
                  in: RoundedRectangle(cornerRadius: 10)
                ).clipped()
              }.buttonStyle(.plain).offset(x: tile.x + 2, y: tile.y + 2).help(
                "\(tile.entry.path) · \(Format.bytes(Double(tile.entry.bytes)))")
            }
          }
        }.frame(height: 260)
        HStack {
          Text("Changes since").font(.system(size: 16, weight: .semibold))
          Picker("Earlier scan", selection: $model.comparisonID) {
            Text("Previous complete scan").tag(Optional<UUID>.none)
            ForEach(
              model.history.snapshots.filter {
                $0.root == current.root && $0.complete && $0.date < current.date
              }
            ) { scan in
              Text(scan.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional(scan.id))
            }
          }.frame(width: 280)
          Spacer()
        }
        if let previous = model.previous, current.complete {
          let changes = current.changes(since: previous)
          if changes.isEmpty { Text("No measured size changes.").foregroundStyle(Color.muted) }
          ForEach(changes.prefix(30)) { change in
            HStack {
              Image(systemName: "folder").foregroundStyle(MonitorTab.disk.color)
              Text(URL(fileURLWithPath: change.path).lastPathComponent).lineLimit(1)
              Spacer()
              Text((change.delta > 0 ? "+" : "−") + Format.bytes(abs(change.delta)))
                .monospacedDigit().foregroundStyle(change.delta > 0 ? .orange : .green)
              Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: change.path)])
              }
            }.padding(12).background(Color.surface, in: RoundedRectangle(cornerRadius: 10))
          }
        } else {
          Text(
            "Save two complete scans of this folder to see growth. Partial scans are never treated as a complete comparison."
          ).foregroundStyle(Color.muted)
        }
      } else {
        Text(
          "Choose a folder and scan it to establish your first baseline. Scanning does not delete files."
        ).foregroundStyle(Color.muted).padding(.vertical, 30)
      }
    }
  }
  private func shortPath(_ path: String) -> String {
    path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
  }
}
func featureHeader(_ title: String, detail: String, symbol: String, color: Color) -> some View {
  HStack(spacing: 18) {
    Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(color).frame(
      width: 58, height: 58
    ).background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    VStack(alignment: .leading, spacing: 7) {
      Text(title).font(.system(size: 25, weight: .semibold))
      Text(detail).font(.system(size: 13)).foregroundStyle(Color.muted)
    }
    Spacer()
  }.padding(24).background(Color.surface, in: RoundedRectangle(cornerRadius: 22))
}
func featureStat(_ title: String, _ value: String, symbol: String) -> some View {
  VStack(alignment: .leading, spacing: 12) {
    Label(title, systemImage: symbol).font(.system(size: 12)).foregroundStyle(Color.muted)
    Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).lineLimit(1)
      .minimumScaleFactor(0.7)
  }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(
    Color.surface, in: RoundedRectangle(cornerRadius: 18))
}
