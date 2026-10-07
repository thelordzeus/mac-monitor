import AppKit
import SwiftUI

/// Section title with an optional item count and up to two trailing actions.
struct PulseSectionHeader<Trailing: View>: View {
  let title: String
  let count: Int?
  @ViewBuilder let trailing: () -> Trailing

  var body: some View {
    HStack(spacing: 6) {
      Text(title).font(PulseType.section)
      if let count {
        Text("\(count)").font(PulseType.caption).monospacedDigit()
          .foregroundStyle(PulseUI.tertiaryText)
      }
      Spacer(minLength: 8)
      trailing()
    }.accessibilityElement(children: .contain).accessibilityAddTraits(.isHeader)
  }
}

/// One-line empty or loading state.
struct PulseEmptyRow: View {
  let text: String
  let isLoading: Bool

  var body: some View {
    HStack(spacing: 8) {
      if isLoading { ProgressView().controlSize(.small) }
      Text(text).font(PulseType.body).foregroundStyle(PulseUI.secondaryText)
    }.frame(maxWidth: .infinity, minHeight: 56)
  }
}

/// Expands a capped list.
struct PulseShowAllButton: View {
  let total: Int
  let noun: String
  @Binding var isExpanded: Bool

  var body: some View {
    Button(isExpanded ? "Show fewer" : "Show all \(total.formatted()) \(noun)") {
      isExpanded.toggle()
    }.pulseButton(.quiet).controlSize(.small)
  }
}

/// Result or error text shown beside the action that produced it.
struct PulseStatusLine: View {
  let text: String
  let tone: PulseStatusTone

  var body: some View {
    Text(text).font(PulseType.body)
      .foregroundStyle(tone == .warning || tone == .critical ? tone.color : PulseUI.supportingText)
      .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Monospaced trailing value column, with an optional second line such as a date.
struct PulseTrailingValue: View {
  let value: String
  let detail: String?

  var body: some View {
    VStack(alignment: .trailing, spacing: 2) {
      Text(value).font(PulseType.numeric).foregroundStyle(PulseUI.supportingText)
      if let detail {
        Text(detail).font(PulseType.caption).foregroundStyle(PulseUI.tertiaryText)
      }
    }.monospacedDigit().lineLimit(1)
  }
}

enum Pasteboard {
  @MainActor static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}

enum Finder {
  @MainActor static func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
  }

  @MainActor static func chooseFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url?.path : nil
  }
}

/// App icon, name, one detail line and an optional warning, shared by Memory and Revive rows.
struct AppRowIdentity: View {
  let app: MemoryApp
  let detail: String?
  let warning: String?

  var body: some View {
    HStack(spacing: 12) {
      AppMemoryIcon(app: app)
      VStack(alignment: .leading, spacing: 2) {
        Text(app.name).font(PulseType.rowTitle).lineLimit(1)
        if let detail {
          Text(detail).font(PulseType.caption).foregroundStyle(PulseUI.secondaryText)
            .lineLimit(1).help(detail)
        }
        if let warning {
          Text(warning).font(PulseType.caption).foregroundStyle(PulseUI.warning)
            .fixedSize(horizontal: false, vertical: true)
        }
      }.frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Search pinned above a scrolling page.
struct PageSearchBar: View {
  let title: String
  @Binding var text: String

  var body: some View {
    PulseSearchField(title: title, text: $text)
      .padding(.horizontal, PulseUI.pagePadding).padding(.vertical, 12)
      .background(PulseUI.canvasBackground)
  }
}

/// Menu row with a trailing checkmark for an on/off choice; menus use buttons, not toggles.
struct MenuCheckLabel: View {
  let title: String
  let isOn: Bool

  var body: some View {
    HStack {
      Text(title)
      Spacer()
      Image(systemName: "checkmark").opacity(isOn ? 1 : 0)
    }.accessibilityValue(isOn ? "On" : "Off")
  }
}

/// Count of items that need the user, on navigation items and buttons.
struct PulseCountBadge: View {
  let count: Int
  let label: String

  var body: some View {
    Text("\(count)").font(PulseType.captionEmphasis).monospacedDigit()
      .foregroundStyle(.black.opacity(0.88))
      .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
      .background(PulseUI.warning, in: .capsule)
      .accessibilityLabel(label)
  }
}

/// Bottom bar for a selection or reclaimable total and its one cleanup action.
struct StorageActionBar: View {
  let summary: String
  /// Shown with a spinner while the action runs.
  let progress: String?
  /// Result of the last action.
  let message: String?
  let actionTitle: String
  /// Accent only for the page's main bulk action; inline section bars stay secondary.
  let emphasis: PulseButtonEmphasis
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if let progress {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(progress).font(PulseType.caption).monospacedDigit()
            .foregroundStyle(PulseUI.secondaryText)
        }
      } else if let message {
        PulseStatusLine(text: message, tone: .working)
      }
      HStack {
        Text(summary).font(PulseType.label).monospacedDigit()
        Spacer()
        Button(actionTitle, action: action).pulseButton(emphasis).disabled(isDisabled)
      }
    }
    .padding(.vertical, 12)
    .overlay(alignment: .top) { PulseRowDivider(leading: 0) }
  }
}
