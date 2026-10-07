import SwiftUI

struct DeveloperCleanupView: View {
  @ObservedObject var model: StorageBreakdownModel
  @State private var ageThreshold = 0
  @State private var dependencyLimit = 20
  @State private var dependencySort = DependencySort.largest
  @State private var dependencyVisibility = DependencyVisibility.canDelete
  @State private var dependencySearch = ""

  /// Every derived list for one render; the filters and sorts run once.
  private struct Listing {
    let all: [StorageItem]
    let matches: [StorageItem]
    let displayed: [StorageItem]
    let generated: [StorageItem]
    let simulatorCache: StorageItem?
    let deletableCount: Int
    let inUseCount: Int
  }

  private var listing: Listing {
    var all: [StorageItem] = []
    var generated: [StorageItem] = []
    var simulatorCache: StorageItem?
    for category in model.categories {
      for item in category.items {
        switch item.cleanupKind {
        case .nodeModules where category.id == "node-modules": all.append(item)
        case .generatedBuildCache where category.id == "node-modules": generated.append(item)
        case .simulatorCache where simulatorCache == nil: simulatorCache = item
        default: break
        }
      }
    }
    let cutoff = Calendar.current.date(byAdding: .day, value: -ageThreshold, to: .now) ?? .now
    let filtered = all.filter { item in
      let matchesVisibility: Bool
      switch dependencyVisibility {
      case .canDelete: matchesVisibility = item.cleanupAvailability?.isReady == true
      case .inUse: matchesVisibility = item.activeProcesses?.isEmpty == false
      case .all: matchesVisibility = true
      }
      let matchesAge = ageThreshold == 0 || (item.lastActivityAt ?? .distantFuture) < cutoff
      let matchesSearch =
        dependencySearch.isEmpty
        || item.name.localizedCaseInsensitiveContains(dependencySearch)
        || item.path.localizedCaseInsensitiveContains(dependencySearch)
      return matchesVisibility && matchesAge && matchesSearch
    }
    let matches =
      switch dependencySort {
      case .largest: filtered.sorted { $0.bytes > $1.bytes }
      case .oldest:
        filtered.sorted {
          ($0.lastActivityAt ?? .distantFuture) < ($1.lastActivityAt ?? .distantFuture)
        }
      }
    return Listing(
      all: all, matches: matches, displayed: Array(matches.prefix(dependencyLimit)),
      generated: generated.sorted { $0.bytes > $1.bytes }, simulatorCache: simulatorCache,
      deletableCount: all.count(where: { $0.cleanupAvailability?.isReady == true }),
      inUseCount: all.count(where: { $0.activeProcesses?.isEmpty == false }))
  }

  var body: some View {
    let listing = listing
    VStack(spacing: 12) {
      PulseStorageSection(
        title: "Dependencies", symbol: "shippingbox.fill",
        detail: dependencyDetail(listing),
        trailing: listing.all.isEmpty
          ? nil : ByteText.full(listing.all.reduce(0) { $0 + $1.bytes }),
        showsContent: !listing.all.isEmpty
      ) {
        nodeControls(listing)
        if dependencyVisibility != .canDelete { DependencyLegend() }
        if listing.matches.isEmpty {
          PulseEmptyRow(
            text: model.isScanning
              ? "Scanning dependency folders…" : "No dependency folders match these filters",
            isLoading: model.isScanning)
        } else {
          LazyVStack(spacing: 0) {
            ForEach(listing.displayed) { item in itemRow(item) }
          }
        }
        if listing.matches.count > dependencyLimit {
          Button("Show next \(min(20, listing.matches.count - dependencyLimit)) folders") {
            dependencyLimit += 20
          }.pulseButton(.quiet).controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }
      }
      .onChange(of: dependencySearch) { _, _ in dependencyLimit = 20 }
      .onChange(of: dependencySort) { _, _ in dependencyLimit = 20 }
      .onChange(of: dependencyVisibility) { _, _ in dependencyLimit = 20 }
      .onChange(of: ageThreshold) { _, _ in dependencyLimit = 20 }

      if !listing.generated.isEmpty {
        PulseStorageSection(
          title: "Build caches", symbol: "hammer.fill", detail: "npm, Vercel, and Trigger outputs",
          trailing: ByteText.full(listing.generated.reduce(0) { $0 + $1.bytes }),
          showsContent: true
        ) {
          ForEach(listing.generated) { item in itemRow(item) }
        }
      }

      if let simulatorCache = listing.simulatorCache {
        PulseStorageSection(
          title: "Simulator cache", symbol: "iphone.gen3", detail: "Temporary simulator data",
          trailing: ByteText.full(simulatorCache.bytes),
          showsContent: true
        ) {
          itemRow(simulatorCache)
        }
      }
    }
  }

  private func dependencyDetail(_ listing: Listing) -> String {
    if !listing.all.isEmpty { return "\(listing.all.count) project folders" }
    return model.isScanning ? "Scanning project folders…" : "No dependency folders found"
  }

  private func itemRow(_ item: StorageItem) -> some View {
    CleanupItemRow(
      item: item,
      isSelected: model.selectedPaths.contains(item.path),
      onSelectionChange: { model.setSelected($0) },
      onStopAndSelect: { model.stopProcessesAndSelect($0) },
      isStoppingProcesses: model.stoppingProcessPath == item.path)
  }

  private func nodeControls(_ listing: Listing) -> some View {
    let selectable = listing.displayed.filter { $0.cleanupAvailability?.isReady == true }
    return VStack(spacing: 9) {
      HStack(spacing: 10) {
        PulseSegmentedPicker(
          title: "Status", options: [DependencyVisibility.canDelete, .inUse, .all],
          selection: $dependencyVisibility,
          label: { value in
            switch value {
            case .canDelete: "Can delete \(listing.deletableCount)"
            case .inUse: "In use \(listing.inUseCount)"
            case .all: "All \(listing.all.count)"
            }
          }
        ).frame(width: 330)
        PulseSearchField(title: "Find a project or path", text: $dependencySearch)
          .frame(minWidth: 180)
      }
      HStack(alignment: .top, spacing: 12) {
        PulseSegmentedPicker(
          title: "Age", options: [0, 7, 30, 90], selection: $ageThreshold,
          label: { $0 == 0 ? "Any age" : "\($0)+ days" })
        PulseSegmentedPicker(
          title: "Sort", options: DependencySort.allCases, selection: $dependencySort,
          label: { $0.rawValue }
        ).frame(width: 200)
      }
      HStack {
        Text(
          "\(listing.displayed.count) of \(listing.matches.count) matches · "
            + ByteText.full(listing.matches.reduce(0) { $0 + $1.bytes })
        )
        .font(PulseType.caption).monospacedDigit().foregroundStyle(PulseUI.secondaryText)
        Spacer()
        Button("Select visible") {
          for item in selectable {
            model.setSelected(StorageSelection(path: item.path, isSelected: true))
          }
        }.pulseButton(.quiet).controlSize(.small).disabled(selectable.isEmpty)
        Button("Clear selection") { model.clearSelection() }
          .pulseButton(.quiet).controlSize(.small).disabled(model.selectedPaths.isEmpty)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(PulseUI.quietFill)
  }
}

struct DeveloperCleanupActions: View {
  @ObservedObject var model: StorageBreakdownModel
  @State private var showsConfirmation = false

  var body: some View {
    let selected = model.selectedItems
    let bytes = selected.reduce(0) { $0 + $1.bytes }
    VStack(spacing: 0) {
      if !selected.isEmpty || model.isCleaning || model.cleanupMessage != nil {
        StorageActionBar(
          summary: "\(selected.count) selected · \(ByteText.full(bytes))",
          progress: model.isCleaning
            ? "Deleting \(model.cleanupCompletedCount) of \(model.cleanupTotalCount)" : nil,
          message: model.cleanupMessage, actionTitle: "Review selected…",
          emphasis: .accent, isDisabled: selected.isEmpty || model.isCleaning,
          action: { showsConfirmation = true }
        ).padding(.horizontal, PulseUI.pagePadding).background(PulseUI.panelBackground)
      }
      if showsConfirmation {
        PulseConfirmation(
          title: "Delete selected items permanently?",
          message:
            "\(selected.count) items, \(ByteText.full(bytes)). This cannot be undone. Rebuild and activity checks run before deletion; changed or busy items are skipped.\n\n"
            + selected.map(\.path).joined(separator: "\n"),
          confirmTitle: "Delete permanently",
          onConfirm: {
            showsConfirmation = false
            model.cleanSelected()
          }, onCancel: { showsConfirmation = false })
      }
    }
  }
}

private struct CleanupItemRow: View {
  let item: StorageItem
  let isSelected: Bool
  let onSelectionChange: (StorageSelection) -> Void
  let onStopAndSelect: (StorageItem) -> Void
  let isStoppingProcesses: Bool
  @State private var showsProcesses = false

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Toggle(
          "Select \(item.name)",
          isOn: Binding(
            get: { isSelected },
            set: { value in
              onSelectionChange(StorageSelection(path: item.path, isSelected: value))
            }
          )
        )
        .toggleStyle(PulseCheckboxStyle(showsLabel: false))
        .disabled(!isReady)

        VStack(alignment: .leading, spacing: 3) {
          Text(item.name).font(PulseType.rowTitle).lineLimit(1)
          Text(item.path).font(PulseType.caption).foregroundStyle(PulseUI.tertiaryText)
            .lineLimit(1).truncationMode(.middle).help(item.path)
        }.frame(maxWidth: .infinity, alignment: .leading)

        PulseTrailingValue(
          value: item.lastActivityAt.map {
            $0.formatted(.relative(presentation: .named))
          } ?? "Unknown",
          detail: "project changed"
        )
        .frame(width: 110, alignment: .trailing)
        .help(
          item.lastActivityAt?.formatted(date: .abbreviated, time: .shortened)
            ?? "Project activity could not be fully checked")

        if let processes = item.activeProcesses, !processes.isEmpty {
          PulseStatusBadge(title: "\(processes.count) running", tone: .warning)
        } else if case .blocked = item.cleanupAvailability {
          StorageAvailabilityLabel(availability: item.cleanupAvailability)
        }

        PulseTrailingValue(
          value: ByteText.full(item.bytes),
          detail: item.contentBytes.flatMap {
            $0 < item.bytes ? "\(ByteText.full($0)) file data" : nil
          }
        )
        .frame(width: 110, alignment: .trailing)
        .help(diskUsageHelp)

        PulseActionMenu(label: "Actions for \(item.name)") {
          Button("Show in Finder") { Finder.reveal(item.path) }
          if let processes = item.activeProcesses, !processes.isEmpty {
            Button(showsProcesses ? "Hide running processes" : "Show running processes") {
              showsProcesses.toggle()
            }
          }
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)

      if showsProcesses, let processes = item.activeProcesses, !processes.isEmpty {
        RunningProcessesDetail(
          item: item,
          processes: processes,
          isStopping: isStoppingProcesses,
          onStopAndSelect: onStopAndSelect
        )
      }
    }
    .overlay(alignment: .bottom) { PulseRowDivider(leading: 42) }
  }

  private var isReady: Bool {
    item.cleanupAvailability?.isReady == true
  }

  private var diskUsageHelp: String {
    guard let contentBytes = item.contentBytes, contentBytes < item.bytes else {
      return "Space this folder consumes on the drive."
    }

    return "The drive reserves whole storage blocks for every file. "
      + "Thousands of tiny dependency files can therefore consume more disk space than their file data."
  }
}

private struct RunningProcessesDetail: View {
  let item: StorageItem
  let processes: [ProjectProcessInfo]
  let isStopping: Bool
  let onStopAndSelect: (StorageItem) -> Void
  @State private var reviewingStop = false

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      HStack {
        Label("Processes using this project", systemImage: "terminal.fill")
          .font(PulseType.captionEmphasis)
        Spacer()

        if isStopping {
          ProgressView().controlSize(.small)
          Text("Stopping…").font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
        } else {
          Button("Stop and select…") { reviewingStop = true }
            .pulseButton(.secondary).controlSize(.small)
        }
      }

      ForEach(processes) { process in
        HStack(spacing: 8) {
          Text(process.name).font(PulseType.label)
          Text("PID \(process.processID)").monospacedDigit()
            .foregroundStyle(PulseUI.secondaryText)
          Spacer()
          Text(process.listeningPorts.isEmpty ? "No listening ports" : portList(process))
            .monospacedDigit().foregroundStyle(PulseUI.secondaryText)
        }
        .font(PulseType.caption)
      }

      if reviewingStop {
        PulseConfirmation(
          title: "Stop running processes?",
          message:
            "Stopping these listed processes can discard unsaved work. Dependencies are selected only after a rescan.",
          confirmTitle: "Stop and select",
          onConfirm: {
            reviewingStop = false
            onStopAndSelect(item)
          }, onCancel: { reviewingStop = false })
      }
    }
    .padding(.leading, 50)
    .padding(.trailing, 14)
    .padding(.vertical, 10)
    .background(PulseUI.warning.opacity(0.055))
    .overlay(alignment: .top) {
      PulseRowDivider(leading: 42)
    }
  }

  private func portList(_ process: ProjectProcessInfo) -> String {
    "Ports "
      + process.listeningPorts.map { port in
        ":\(port)"
      }.joined(separator: ", ")
  }
}

private struct DependencyLegend: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      Label {
        Text(
          "In use · protected: a dev server, Terminal, Codex, or another app is using the project.")
      } icon: {
        Image(systemName: "lock.fill")
          .foregroundStyle(PulseUI.warning)
      }

      Label {
        Text(
          "On disk is the space consumed. Tiny dependency files can use more space than their file data."
        )
      } icon: {
        Image(systemName: "externaldrive.fill")
          .foregroundStyle(PulseUI.secondaryText)
      }
    }
    .font(PulseType.caption)
    .foregroundStyle(PulseUI.secondaryText)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

private enum DependencySort: String, CaseIterable, Identifiable {
  case largest = "Largest"
  case oldest = "Oldest"

  var id: Self {
    self
  }
}

private enum DependencyVisibility: String, CaseIterable, Identifiable {
  case canDelete
  case inUse
  case all

  var id: Self {
    self
  }
}

private struct StorageAvailabilityLabel: View {
  let availability: StorageCleanupAvailability?

  var body: some View {
    PulseStatusBadge(title: label, tone: tone).help(helpText)
  }

  private var label: String {
    switch availability {
    case .ready:
      return "Selectable"
    case .blocked(let reason):
      return blockedLabel(reason)
    case nil:
      return "Review"
    }
  }

  private var helpText: String {
    switch availability {
    case .ready:
      return "This dependency folder can be selected and reinstalled from the project lockfile."
    case .blocked(let reason):
      return blockedHelp(reason)
    case nil:
      return "\(AppBrand.name) cannot verify that this item is safe to delete automatically."
    }
  }

  private func blockedLabel(_ reason: String) -> String {
    switch reason {
    case "Project is in use":
      return "In use · protected"
    case "No exact reinstall lock":
      return "Lockfile missing"
    case "Missing package.json":
      return "Not a project"
    default:
      return reason
    }
  }

  private func blockedHelp(_ reason: String) -> String {
    switch reason {
    case "Project is in use":
      return
        "A running process has this project open. Stop its dev server or task, then scan again."
    case "No exact reinstall lock":
      return
        "No npm, pnpm, Yarn, or Bun lockfile was found, so an exact reinstall is not guaranteed."
    case "Missing package.json":
      return "No package.json was found for this dependency folder."
    default:
      return reason
    }
  }

  private var tone: PulseStatusTone {
    switch availability {
    case .ready: .good
    case .blocked: .warning
    case nil: .muted
    }
  }
}

struct DockerStorageView: View {
  @ObservedObject var model: DockerStorageModel
  @State private var showsConfirmation = false

  var body: some View {
    let reclaimable = model.snapshot?.rebuildableBytes ?? 0
    VStack(spacing: 0) {
      if let errorMessage = model.errorMessage {
        PulseStatusLine(text: errorMessage, tone: .warning).padding(16)
        PulseRowDivider(leading: 0)
      }
      if let snapshot = model.snapshot {
        ForEach(snapshot.categories) { category in
          DockerCategoryRow(category: category)
          if category.id != snapshot.categories.last?.id { PulseRowDivider(leading: 52) }
        }
        Text(
          "\(ByteText.full(snapshot.totalBytes)) allocated · updated \(snapshot.updatedAt.formatted(.relative(presentation: .named)))"
        )
        .font(PulseType.caption).foregroundStyle(PulseUI.tertiaryText)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16)
        .padding(.vertical, 10)
      } else if model.isRefreshing {
        PulseEmptyRow(
          text: "Reading images, containers, volumes, and build cache…", isLoading: true)
      } else if !model.isInstalled {
        PulseEmptyRow(text: "Docker Desktop is not installed", isLoading: false)
      }
      if model.snapshot != nil || model.isCleaning || model.cleanupMessage != nil {
        StorageActionBar(
          summary: "\(ByteText.full(reclaimable)) reclaimable",
          progress: model.isCleaning ? "Deleting unused Docker images and build cache…" : nil,
          message: model.cleanupMessage, actionTitle: "Review Docker cleanup…",
          emphasis: .secondary,
          isDisabled: reclaimable == 0 || model.isCleaning || model.isRefreshing,
          action: { showsConfirmation = true }
        ).padding(.horizontal, 16)
      }
      if showsConfirmation {
        PulseConfirmation(
          title: "Delete unused Docker images and build cache?",
          message:
            "\(ByteText.full(reclaimable)) of unused images and build cache will be deleted permanently. Containers and volumes will not be deleted.",
          confirmTitle: "Delete unused images and cache",
          onConfirm: {
            showsConfirmation = false
            model.cleanRebuildable()
          }, onCancel: { showsConfirmation = false })
      }
    }
    .task { model.refreshIfNeeded() }
  }
}

private struct DockerCategoryRow: View {
  let category: DockerStorageCategory

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage).foregroundStyle(PulseUI.secondaryText).frame(width: 26)
      VStack(alignment: .leading, spacing: 3) {
        Text(category.name).font(PulseType.rowTitle)
        Text("\(category.totalCount) total · \(category.activeCount) active")
          .font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
      }
      Spacer()
      if category.isProtected {
        PulseStatusBadge(title: "Protected", tone: .muted)
      }
      PulseTrailingValue(
        value: ByteText.full(category.sizeBytes),
        detail: category.reclaimableBytes > 0
          ? "\(ByteText.full(category.reclaimableBytes)) reclaimable" : nil
      ).frame(width: 150, alignment: .trailing)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var systemImage: String {
    switch category.id {
    case "images": "square.stack.3d.up.fill"
    case "containers": "shippingbox.fill"
    case "volumes": "externaldrive.fill"
    case "build-cache": "hammer.fill"
    default: "circle.grid.2x2.fill"
    }
  }
}
