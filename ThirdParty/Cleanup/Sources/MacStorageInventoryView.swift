import AppKit
import SwiftUI

@MainActor struct MacStorageInventoryView: View {
  @ObservedObject var model: StorageBreakdownModel
  @ObservedObject private var caches: InventoryCacheModel
  let onBrowse: (String) -> Void
  @StateObject private var leftovers = AppLeftoverModel()
  @State private var showsLeftovers = false
  @State private var query = ""
  @State private var showingAll: Set<String> = []
  @State private var pendingApp: StorageItem?
  @State private var status: Status?

  init(model: StorageBreakdownModel, onBrowse: @escaping (String) -> Void) {
    self.model = model
    self.onBrowse = onBrowse
    self.caches = model.inventoryCaches
  }

  private var selectionEnabled: Bool {
    !caches.isBusy && caches.review.isEmpty && pendingApp == nil
  }

  private func refreshCacheOwners() {
    guard let category = model.categories.first(where: { $0.id == "computer-user-caches" }) else { return }
    let apps = model.categories.first(where: { $0.id == "computer-applications" })?.items ?? []
    caches.update(items: category.items, catalog: .installed(apps))
  }

  private struct Status {
    let text: String
    let tone: PulseStatusTone
  }

  private struct Section: Identifiable {
    let category: StorageCategory
    let items: [StorageItem]
    var id: String { category.id }
    var isDeveloper: Bool { !category.id.hasPrefix("computer-") && category.id != "large-files" }
  }

  private static let order = [
    "computer-applications", "computer-xcode", "computer-user-caches", "large-files",
    "computer-personal-files", "computer-library-data", "computer-system-data", "node-modules",
  ]

  /// Sorted, query-filtered sections computed once per render.
  private var sections: [Section] {
    model.categories.filter { !$0.items.isEmpty }
      .sorted { left, right in
        let leftIndex = Self.order.firstIndex(of: left.id) ?? Self.order.count
        let rightIndex = Self.order.firstIndex(of: right.id) ?? Self.order.count
        return leftIndex == rightIndex ? left.bytes > right.bytes : leftIndex < rightIndex
      }
      .map { category in
        let sorted = category.items.sorted { $0.bytes > $1.bytes }
        return Section(
          category: category,
          items: query.isEmpty
            ? sorted
            : sorted.filter {
              $0.name.localizedCaseInsensitiveContains(query)
                || $0.path.localizedCaseInsensitiveContains(query)
                || (category.id == "computer-user-caches"
                  && caches.owners[$0.path]?.name.localizedCaseInsensitiveContains(query) == true)
            })
      }
      .filter { query.isEmpty || !$0.items.isEmpty }
  }

  var body: some View {
    let sections = sections
    let developer = sections.filter(\.isDeveloper)
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 16) {
        HStack {
          PulseSearchField(title: "Search apps, files, and folders", text: $query)
          Button("Browse folders") {
            onBrowse(FileManager.default.homeDirectoryForCurrentUser.path)
          }.pulseButton(.quiet)
          Button("Scan Mac") { model.scan() }.pulseButton(.secondary)
            .disabled(model.isScanning || caches.isBusy || !caches.review.isEmpty)
        }
        HStack(spacing: 8) {
          if model.isScanning {
            ProgressView().controlSize(.small)
            Text("Measuring apps and folders…")
          } else if let scannedAt = model.inventoryScannedAt {
            Text("Scanned \(scannedAt.formatted(date: .abbreviated, time: .shortened))")
              .help(
                "Allocated disk space. Categories can overlap. Protected locations require Full Disk Access; large files use Spotlight."
              )
          }
        }.font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
        if let status { PulseStatusLine(text: status.text, tone: status.tone) }
        if let message = caches.status {
          PulseStatusLine(text: message, tone: caches.failures.isEmpty ? .muted : .warning)
        }
        if sections.isEmpty && !model.isScanning {
          PulseEmptyRow(
            text: query.isEmpty
              ? "No inventory yet. Scan Mac to measure apps and folders."
              : "Nothing named \(query) found",
            isLoading: false)
        }
        inventorySections(sections.filter { !$0.isDeveloper })
        if !developer.isEmpty {
          Text("Developer data").font(PulseType.section).foregroundStyle(PulseUI.secondaryText)
            .padding(.top, 8)
          inventorySections(developer)
        }
      }.padding(PulseUI.pagePadding)
    }
    .sheet(isPresented: $showsLeftovers) { AppLeftoversView(model: leftovers, history: model.overview, finished: { model.scan() }) }
    .task { refreshCacheOwners(); model.scanIfNeeded() }
    .onChange(of: model.categories) { _, _ in refreshCacheOwners() }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      if let pendingApp {
        PulseConfirmation(
          title: "Move \(pendingApp.name) to Trash?",
          message:
            "Moves the app bundle only. Support files may remain. Empty Trash to reclaim space.",
          confirmTitle: "Move app to Trash",
          onConfirm: {
            let app = pendingApp
            self.pendingApp = nil
            trash(app)
          }, onCancel: { self.pendingApp = nil })
      } else if !caches.review.isEmpty {
        PulseConfirmation(
          title: "Move \(caches.review.count) selected \(caches.review.count == 1 ? "cache" : "caches") to Trash?",
          message: "\(ByteText.full(caches.reviewedBytes)) selected. Apps may download cached data again. Empty Trash to reclaim space.\n\n"
            + caches.review.map { "\($0.owner.name) · \(abbreviated($0.id))" }.joined(separator: "\n"),
          confirmTitle: "Move caches to Trash",
          onConfirm: { caches.moveReviewed(history: model.overview, onCompletion: { model.scan() }) },
          onCancel: { caches.cancelReview() })
      } else if caches.isBusy || !caches.selected.isEmpty {
        HStack(spacing: 12) {
          if caches.isBusy {
            ProgressView().controlSize(.small)
            Text(caches.status ?? "Checking caches…").font(PulseType.caption)
            Spacer()
            if caches.isPreparing {
              Button("Cancel review") { caches.cancelPreparation() }.pulseButton(.quiet)
            }
          } else {
            Text("\(caches.selected.count) \(caches.selected.count == 1 ? "cache" : "caches") selected · \(ByteText.full(caches.selectedBytes))")
              .font(PulseType.caption).monospacedDigit()
            Spacer()
            Button("Clear selection") { caches.selected = [] }.pulseButton(.quiet)
            Button("Move selected to Trash…", role: .destructive) { caches.prepare() }
              .pulseButton(.secondary)
          }
        }.padding(.horizontal, PulseUI.pagePadding).padding(.vertical, 12)
          .background(PulseUI.panelBackground)
          .overlay(alignment: .top) { Rectangle().fill(PulseUI.separator).frame(height: 1) }
      }
    }
  }

  private func inventorySections(_ sections: [Section]) -> some View {
    ForEach(sections) { section in
      let expanded = !query.isEmpty || showingAll.contains(section.id)
      let displayed = expanded ? section.items : Array(section.items.prefix(6))
      PulseStorageSection(
        title: section.category.name, symbol: section.category.systemImage,
        detail: section.id == "computer-user-caches"
          ? "Select caches to move to Trash; close their apps before removal"
          : section.category.detail,
        trailing: ByteText.full(section.category.bytes),
        showsContent: true
      ) {
        LazyVStack(spacing: 0) {
          if section.id == "computer-user-caches" {
            Toggle("Select all \(section.items.count) caches", isOn: Binding(
              get: { !section.items.isEmpty && section.items.allSatisfy { caches.selected.contains($0.path) } },
              set: { selected in
                guard selectionEnabled else { return }
                let paths = Set(section.items.map(\.path))
                if selected { caches.selected.formUnion(paths) } else { caches.selected.subtract(paths) }
              }))
              .toggleStyle(PulseCheckboxStyle()).font(PulseType.caption)
              .disabled(!selectionEnabled)
              .help("Select all caches matching this search, including collapsed rows.")
              .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6)
            PulseRowDivider(leading: 0)
          }
          ForEach(displayed) { item in
            itemRow(.init(item: item, category: section.category))
            if item.id != displayed.last?.id {
              PulseRowDivider(leading: section.id == "computer-user-caches" ? 100 : 54)
            }
          }
          if query.isEmpty && section.items.count > 6 {
            PulseRowDivider(leading: 0)
            PulseShowAllButton(
              total: section.items.count, noun: "items",
              isExpanded: Binding(
                get: { showingAll.contains(section.id) },
                set: {
                  if $0 { showingAll.insert(section.id) } else { showingAll.remove(section.id) }
                }
              )
            ).padding(.vertical, 8)
          }
        }
      }
    }
  }

  private struct RowInput {
    let item: StorageItem
    let category: StorageCategory
  }

  private func itemRow(_ input: RowInput) -> some View {
    let item = input.item
    let category = input.category
    let isCache = category.id == "computer-user-caches"
    let owner = isCache ? caches.owners[item.path] : nil
    return HStack(spacing: 12) {
      if isCache {
        Toggle("Select cache for \(owner?.name ?? item.name)", isOn: Binding(
          get: { caches.selected.contains(item.path) },
          set: { selected in
            guard selectionEnabled else { return }
            if selected { caches.selected.insert(item.path) } else { caches.selected.remove(item.path) }
          }))
          .toggleStyle(PulseCheckboxStyle(showsLabel: false)).disabled(!selectionEnabled)
          .help("Select \(abbreviated(item.path))")
        if let appPath = owner?.applicationPath {
          ApplicationIcon(source: .file(appPath), size: 26, fallback: "app")
        } else {
          Image(systemName: owner?.fallbackSymbol ?? "shippingbox")
            .frame(width: 26).foregroundStyle(PulseUI.secondaryText).accessibilityHidden(true)
        }
      } else if category.id == "computer-applications" {
        ApplicationIcon(source: .file(item.path), size: 26, fallback: "app")
      } else {
        Image(systemName: category.id == "large-files" ? "doc" : "folder")
          .frame(width: 26).foregroundStyle(PulseUI.secondaryText)
      }
      VStack(alignment: .leading, spacing: 3) {
        Text(owner?.name ?? item.name).font(PulseType.rowTitle).lineLimit(1)
        Text(isCache ? abbreviated(item.path) : item.path).font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
          .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        if isCache, let failure = caches.failures[item.path] {
          Text(failure).font(PulseType.caption).foregroundStyle(PulseUI.warning)
            .fixedSize(horizontal: false, vertical: true)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
      PulseTrailingValue(value: ByteText.full(item.bytes), detail: nil)
      Button("Show in Finder") { Finder.reveal(item.path) }.pulseButton(.quiet)
        .controlSize(.small)
      if !item.path.hasSuffix(".app"), DirectoryCheck.isDirectory(item.path) {
        Button("Browse") { onBrowse(item.path) }.pulseButton(.secondary).controlSize(.small)
      } else if category.id == "computer-applications", canTrash(item) {
        Menu {
          Button("Review app and associated files…") { showsLeftovers = true; leftovers.scan(item.path) }
          Button("Move app to Trash…", role: .destructive) { pendingApp = item }
        } label: {
          Image(systemName: "ellipsis")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PulseUI.secondaryText)
            .frame(width: 34, height: 34).contentShape(Rectangle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).disabled(!selectionEnabled)
          .fixedSize().accessibilityLabel("Actions for \(item.name)")
          .help("Actions for \(item.name)")
      }
    }.pulseRow()
  }

  private func abbreviated(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
  }

  private func canTrash(_ item: StorageItem) -> Bool {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return item.path.hasSuffix(".app")
      && (item.path.hasPrefix("/Applications/")
        || item.path.hasPrefix(home + "/Applications/"))
  }

  private func trash(_ item: StorageItem) {
    guard canTrash(item),
      ReviewFile.canonicalPath(item.path) == item.path,
      FileManager.default.fileExists(atPath: item.path)
    else {
      status = .init(
        text: "The app moved or changed. Scan again before uninstalling.", tone: .warning)
      return
    }
    let running = NSWorkspace.shared.runningApplications.contains { app in
      app.bundleURL?.path == item.path
    }
    guard !running else {
      status = .init(text: "Quit \(item.name) before uninstalling it.", tone: .warning)
      return
    }
    do {
      let before = CleanupVolume.read(item.path)
      let receipt = try TrashRecovery.trash(item.path)
      model.overview.record(.init(id: UUID().uuidString, date: .now, title: "Moved \(item.name) to Trash", paths: [item.path], before: before, after: before.flatMap { CleanupVolume.read($0.path) }, bytes: item.bytes, recovery: receipt.map { [$0] }))
      status = .init(
        text: "\(item.name) moved to Trash. Empty Trash to reclaim space.", tone: .working)
      model.scan()
    } catch {
      status = .init(
        text: "Could not move \(item.name) to Trash: \(error.localizedDescription)", tone: .warning)
    }
  }
}

/// Remembers whether an inventory path is a folder, so rows avoid a file-system call per render.
@MainActor
private enum DirectoryCheck {
  private static var cache: [String: Bool] = [:]

  static func isDirectory(_ path: String) -> Bool {
    if let known = cache[path] { return known }
    let value =
      (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
      == true
    if cache.count > 4_000 { cache.removeAll() }
    cache[path] = value
    return value
  }
}
