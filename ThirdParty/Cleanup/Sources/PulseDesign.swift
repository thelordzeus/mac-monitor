import AppKit
import SwiftUI

enum PulseType {
  static let largeTitle = Font.system(size: 24, weight: .semibold)
  static let title = Font.system(size: 17, weight: .semibold)
  static let headline = Font.system(size: 15, weight: .semibold)
  static let section = Font.system(size: 13, weight: .semibold)
  static let callout = Font.system(size: 13)
  static let rowTitle = Font.system(size: 13, weight: .medium)
  static let body = Font.system(size: 12)
  static let label = Font.system(size: 12, weight: .medium)
  static let caption = Font.system(size: 11)
  static let captionEmphasis = Font.system(size: 11, weight: .medium)
  static let numeric = Font.system(size: 12).monospacedDigit()
}

enum PulseUI {
  static let mint = Color(red: 0.20, green: 0.78, blue: 0.65)
  static let lavender = mint
  static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
  static let recordRed = Color(red: 1.0, green: 0.27, blue: 0.27)
  static let canvasBackground = Color(red: 27 / 255, green: 27 / 255, blue: 30 / 255)
  static let panelBackground = Color(red: 34 / 255, green: 34 / 255, blue: 36 / 255)
  static let sidebarBackground = panelBackground
  static let menuFill = Color(white: 0.13)
  static let panelStroke = Color.white.opacity(0.10)
  static let separator = Color.white.opacity(0.08)
  static let cardFill = panelBackground
  static let quietFill = Color.white.opacity(0.045)
  static let controlFill = Color.white.opacity(0.055)
  static let hoverFill = Color.white.opacity(0.075)
  static let selectedFill = Color.white.opacity(0.10)
  static let strongFill = Color.white.opacity(0.16)
  static let strongStroke = Color.white.opacity(0.22)
  static let primaryText = Color.white.opacity(0.92)
  static let supportingText = Color.white.opacity(0.72)
  static let secondaryText = Color(red: 150 / 255, green: 150 / 255, blue: 158 / 255)
  static let tertiaryText = Color.white.opacity(0.46)
  static let controlRadius: CGFloat = 8
  static let cardRadius: CGFloat = 22
  static let pagePadding: CGFloat = 24
  static let toolbarHeight: CGFloat = 52
  static let titleFont = PulseType.largeTitle
  static let valueFont = Font.system(size: 36, weight: .semibold, design: .rounded)

  static func sectionLabel(_ title: String) -> some View {
    Text(title).font(PulseType.captionEmphasis).foregroundStyle(secondaryText).lineLimit(1)
  }
}

enum PulseButtonEmphasis {
  case accent, emphasized, secondary, quiet
}

enum PulseControlMetrics {
  static func height(_ size: ControlSize) -> CGFloat {
    switch size {
    case .mini: 24
    case .small: 28
    case .large, .extraLarge: 40
    default: 34
    }
  }

  static func fontSize(_ size: ControlSize) -> CGFloat {
    switch size {
    case .mini, .small: 11
    case .large, .extraLarge: 13
    default: 12
    }
  }

  static func horizontalPadding(_ size: ControlSize) -> CGFloat {
    switch size {
    case .mini, .small: 8
    case .large, .extraLarge: 16
    default: 10
    }
  }
}

struct PulseButtonStyle: ButtonStyle {
  let emphasis: PulseButtonEmphasis
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.controlSize) private var controlSize
  @State private var isHovered = false

  init(_ emphasis: PulseButtonEmphasis) {
    self.emphasis = emphasis
  }

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: PulseControlMetrics.fontSize(controlSize), weight: .medium))
      .lineLimit(1)
      .symbolRenderingMode(.monochrome)
      .padding(.horizontal, PulseControlMetrics.horizontalPadding(controlSize))
      .padding(.vertical, 4)
      .frame(minHeight: PulseControlMetrics.height(controlSize))
      .foregroundStyle(foreground(configuration.role))
      .background(fill, in: RoundedRectangle(cornerRadius: PulseUI.controlRadius))
      .overlay {
        RoundedRectangle(cornerRadius: PulseUI.controlRadius)
          .strokeBorder(emphasis == .secondary ? PulseUI.panelStroke : .clear, lineWidth: 1)
          .allowsHitTesting(false)
      }
      .scaleEffect(configuration.isPressed && isEnabled ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
      .opacity(isEnabled ? (configuration.isPressed ? 0.88 : 1) : 0.4)
      .contentShape(RoundedRectangle(cornerRadius: PulseUI.controlRadius))
      .onHover { isHovered = $0 }
      .pulsePointingHand()
  }

  private func foreground(_ role: ButtonRole?) -> Color {
    if role == .destructive, emphasis != .accent { return PulseUI.recordRed }
    switch emphasis {
    case .accent, .emphasized: return .black.opacity(0.88)
    case .secondary: return PulseUI.primaryText
    case .quiet: return isHovered && isEnabled ? PulseUI.primaryText : PulseUI.secondaryText
    }
  }

  private var fill: Color {
    let hovered = isHovered && isEnabled
    switch emphasis {
    case .accent: return hovered ? PulseUI.mint.opacity(0.9) : PulseUI.mint
    case .emphasized: return hovered ? .white : PulseUI.primaryText
    case .secondary: return hovered ? PulseUI.hoverFill : PulseUI.controlFill
    case .quiet: return hovered ? PulseUI.quietFill : .clear
    }
  }
}

extension View {
  func pulseButton(_ emphasis: PulseButtonEmphasis) -> some View {
    buttonStyle(PulseButtonStyle(emphasis))
  }

  @ViewBuilder func pulsePointingHand() -> some View {
    if #available(macOS 15.0, *) {
      pointerStyle(.link).allowsWindowActivationEvents(true)
    } else {
      self
    }
  }

  func pulseInput() -> some View {
    textFieldStyle(.plain).font(PulseType.callout)
      .padding(.horizontal, 12).frame(height: 38)
      .background(PulseUI.controlFill, in: RoundedRectangle(cornerRadius: PulseUI.controlRadius))
      .overlay {
        RoundedRectangle(cornerRadius: PulseUI.controlRadius).strokeBorder(PulseUI.panelStroke)
      }
  }

  func pulseTheme() -> some View {
    self
      .background(PulseUI.canvasBackground.ignoresSafeArea())
      .foregroundStyle(PulseUI.primaryText)
      .tint(PulseUI.mint)
      .buttonStyle(PulseButtonStyle(.secondary))
      .toggleStyle(PulseCheckboxStyle())
      .preferredColorScheme(.dark)
  }
}

struct PulseSelectionButtonStyle: ButtonStyle {
  let isSelected: Bool
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .foregroundStyle(isSelected ? PulseUI.primaryText : PulseUI.secondaryText)
      .background(
        isSelected ? PulseUI.selectedFill : isHovered ? PulseUI.quietFill : .clear,
        in: RoundedRectangle(cornerRadius: 6)
      )
      .contentShape(RoundedRectangle(cornerRadius: 6))
      .opacity(isEnabled ? configuration.isPressed ? 0.76 : 1 : 0.4)
      .onHover { isHovered = $0 }
      .pulsePointingHand()
  }
}

extension View {
  func pulseChipGroup() -> some View {
    padding(2)
      .background(PulseUI.controlFill, in: RoundedRectangle(cornerRadius: PulseUI.controlRadius))
  }
}

struct PulseSegmentedPicker<Value: Hashable>: View {
  let title: String
  let options: [Value]
  @Binding var selection: Value
  let label: (Value) -> String
  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.self) { value in
        Button {
          selection = value
        } label: {
          Text(label(value)).font(PulseType.label).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30).padding(.horizontal, 10)
            .contentShape(Rectangle())
        }.buttonStyle(PulseSelectionButtonStyle(isSelected: value == selection))
          .accessibilityAddTraits(selection == value ? .isSelected : [])
      }
    }.pulseChipGroup()
      .accessibilityElement(children: .contain).accessibilityLabel(title)
  }
}

struct PulseChip: View {
  let title: String
  let symbol: String
  let isSelected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(PulseType.label).lineLimit(1).fixedSize()
        .padding(.horizontal, 10).frame(minHeight: 30).contentShape(Rectangle())
    }.buttonStyle(PulseSelectionButtonStyle(isSelected: isSelected))
      .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

struct PulseProcessButton: View {
  let title: String
  let label: String
  let isBusy: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 6) {
        if isBusy { ProgressView().controlSize(.mini) }
        Text(title)
      }.frame(minWidth: 42)
    }.pulseButton(.secondary).controlSize(.regular)
      .disabled(isBusy).accessibilityLabel(label)
  }
}

struct PulseSearchField: View {
  let title: String
  @Binding var text: String
  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
        .foregroundStyle(PulseUI.tertiaryText)
      TextField(title, text: $text).textFieldStyle(.plain).focused($focused)
        .font(PulseType.body)
        .accessibilityLabel(title)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(PulseUI.tertiaryText)
        }.buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
      }
    }.padding(.horizontal, 10).frame(height: 34)
      .background(PulseUI.controlFill, in: RoundedRectangle(cornerRadius: PulseUI.controlRadius))
      .overlay {
        RoundedRectangle(cornerRadius: PulseUI.controlRadius)
          .strokeBorder(focused ? PulseUI.mint.opacity(0.6) : PulseUI.panelStroke, lineWidth: 1)
          .allowsHitTesting(false)
      }
  }
}

struct PulsePageHeader<Actions: View>: View {
  let title: String
  var detail: String? = nil
  @ViewBuilder let actions: () -> Actions

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(PulseType.largeTitle).tracking(-0.4)
          .foregroundStyle(PulseUI.primaryText)
        if let detail {
          Text(detail).font(PulseType.body).foregroundStyle(PulseUI.secondaryText)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 16)
      actions()
    }
    .padding(.horizontal, PulseUI.pagePadding)
    .padding(.top, 20)
    .padding(.bottom, 18)
    .background {
      Color.clear.contentShape(Rectangle()).pulseWindowDrag()
    }
  }
}

enum PulseStatusTone: Equatable {
  case good, working, warning, critical, muted

  var color: Color {
    switch self {
    case .good: PulseUI.mint
    case .working: PulseUI.supportingText
    case .warning: PulseUI.warning
    case .critical: PulseUI.recordRed
    case .muted: PulseUI.tertiaryText
    }
  }
}

struct PulseStatusDot: View {
  let tone: PulseStatusTone
  var diameter: CGFloat = 6

  var body: some View {
    Circle().fill(tone.color).frame(width: diameter, height: diameter)
      .accessibilityHidden(true)
  }
}

struct PulseStatusBadge: View {
  let title: String
  let tone: PulseStatusTone

  var body: some View {
    HStack(spacing: 6) {
      PulseStatusDot(tone: tone, diameter: 5)
      Text(title).font(PulseType.captionEmphasis).lineLimit(1)
    }
    .foregroundStyle(tone == .muted || tone == .working ? PulseUI.secondaryText : tone.color)
    .padding(.horizontal, 9)
    .frame(height: 24)
    .background(
      (tone == .muted || tone == .working ? Color.white : tone.color).opacity(0.08), in: .capsule)
  }
}

struct PulseActionMenu<Content: View>: View {
  let label: String
  var title: String? = nil
  var symbol = "ellipsis"
  @ViewBuilder let content: () -> Content
  @State private var expanded = false
  @State private var menuHeight: CGFloat = 160
  @State private var hovered = false
  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    Button {
      expanded.toggle()
    } label: {
      HStack(spacing: 8) {
        if let title { Text(title).font(PulseType.label) }
        Image(systemName: title == nil ? symbol : expanded ? "chevron.up" : "chevron.down")
          .font(.system(size: 12, weight: .semibold))
      }
      .foregroundStyle(hovered || expanded ? PulseUI.primaryText : PulseUI.secondaryText)
      .padding(.horizontal, 10).frame(minWidth: 34, minHeight: 34).contentShape(Rectangle())
      .background(
        expanded ? PulseUI.selectedFill : hovered ? PulseUI.quietFill : .clear,
        in: RoundedRectangle(cornerRadius: PulseUI.controlRadius))
    }.buttonStyle(.plain).accessibilityLabel(label).help(label)
      .opacity(isEnabled ? 1 : 0.4)
      .onHover { hovered = $0 }
      .pulsePointingHand()
      .anchorPreference(key: PulseDropdownPreference.self, value: .bounds) { anchor in
        expanded
          ? PulseDropdownPresentation(
            anchor: anchor, width: 264, alignsLeading: title != nil, height: menuHeight,
            content: AnyView(
              VStack(alignment: .leading, spacing: 2) {
                content().buttonStyle(PulseMenuActionStyle()).toggleStyle(PulseMenuToggleStyle())
              }.padding(6)
                .environment(\.pulseDismissMenu, { expanded = false })
                .disabled(!isEnabled)
                .background {
                  GeometryReader { proxy in
                    Color.clear.onAppear { menuHeight = proxy.size.height }
                      .onChange(of: proxy.size.height) { _, height in menuHeight = height }
                  }
                }
            ), dismiss: { expanded = false }) : nil
      }
      .onExitCommand { expanded = false }
      .onChange(of: isEnabled) { _, enabled in if !enabled { expanded = false } }
      .onDisappear { expanded = false }
  }
}

private struct PulseMenuToggleStyle: ToggleStyle {
  @Environment(\.pulseDismissMenu) private var dismiss

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
      dismiss()
    } label: {
      HStack {
        configuration.label
        Spacer()
        Image(systemName: "checkmark").opacity(configuration.isOn ? 1 : 0)
      }
    }.buttonStyle(PulseMenuItemStyle()).accessibilityValue(configuration.isOn ? "On" : "Off")
  }
}

private struct PulseMenuDismissKey: EnvironmentKey {
  static let defaultValue: @MainActor @Sendable () -> Void = {}
}

extension EnvironmentValues {
  fileprivate var pulseDismissMenu: @MainActor @Sendable () -> Void {
    get { self[PulseMenuDismissKey.self] }
    set { self[PulseMenuDismissKey.self] = newValue }
  }
}

private struct PulseMenuActionStyle: PrimitiveButtonStyle {
  @Environment(\.pulseDismissMenu) private var dismiss

  func makeBody(configuration: Configuration) -> some View {
    Button(role: configuration.role) {
      configuration.trigger()
      dismiss()
    } label: {
      configuration.label
    }.buttonStyle(PulseMenuItemStyle())
  }
}

private struct PulseMenuItemStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.font(PulseType.callout)
      .foregroundStyle(
        configuration.role == .destructive ? PulseUI.recordRed : PulseUI.primaryText
      )
      .lineLimit(2).multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
      .padding(.horizontal, 10)
      .modifier(PulseRowHighlight(isPressed: configuration.isPressed, radius: 6))
      .opacity(isEnabled ? 1 : 0.4)
  }
}

/// Hover and pressed fill shared by every full-row button: menus, browser rows, tray rows.
private struct PulseRowHighlight: ViewModifier {
  let isPressed: Bool
  let radius: CGFloat
  @State private var hovered = false
  @Environment(\.isEnabled) private var isEnabled

  func body(content: Content) -> some View {
    content
      .background(
        isPressed ? PulseUI.selectedFill : hovered && isEnabled ? PulseUI.hoverFill : .clear,
        in: RoundedRectangle(cornerRadius: radius)
      )
      .contentShape(RoundedRectangle(cornerRadius: radius))
      .onHover { hovered = $0 }
      .pulsePointingHand()
  }
}

struct PulseRowButtonStyle: ButtonStyle {
  var radius: CGFloat = 0

  func makeBody(configuration: Configuration) -> some View {
    configuration.label.modifier(
      PulseRowHighlight(isPressed: configuration.isPressed, radius: radius))
  }
}

/// A whole card that opens something: faint hover wash and a small press scale.
struct PulseCardButtonStyle: ButtonStyle {
  @State private var hovered = false

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .overlay {
        RoundedRectangle(cornerRadius: PulseUI.cardRadius)
          .fill(Color.white.opacity(hovered ? 0.03 : 0)).allowsHitTesting(false)
      }
      .contentShape(RoundedRectangle(cornerRadius: PulseUI.cardRadius))
      .scaleEffect(configuration.isPressed ? 0.98 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
      .onHover { hovered = $0 }
      .pulsePointingHand()
  }
}

struct PulseChevron: View {
  var body: some View {
    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
      .foregroundStyle(PulseUI.tertiaryText).accessibilityHidden(true)
  }
}

extension View {
  /// Severity-tinted surface for alerts.
  func pulseToneCard(_ tone: MetricTone, radius: CGFloat = PulseUI.cardRadius) -> some View {
    background(tone.color.opacity(0.08), in: RoundedRectangle(cornerRadius: radius))
      .overlay {
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(tone.color.opacity(0.22), lineWidth: 1).allowsHitTesting(false)
      }
  }
}

private struct PulseRowModifier: ViewModifier {
  @State private var hovered = false

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 16).padding(.vertical, 10)
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
      .background(hovered ? PulseUI.quietFill : .clear)
      .contentShape(Rectangle())
      .onHover { hovered = $0 }
  }
}

struct PulseRowDivider: View {
  var leading: CGFloat = 56

  var body: some View {
    Rectangle().fill(PulseUI.separator).frame(height: 1).padding(.leading, leading)
  }
}

private struct PulseWindowDragModifier: ViewModifier {
  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content.gesture(WindowDragGesture()).allowsWindowActivationEvents(true)
    } else {
      content
    }
  }
}

extension View {
  func pulseRow() -> some View { modifier(PulseRowModifier()) }

  func pulseWindowDrag() -> some View { modifier(PulseWindowDragModifier()) }

  func pulseTable() -> some View {
    background(PulseUI.cardFill)
      .clipShape(RoundedRectangle(cornerRadius: PulseUI.cardRadius))
      .overlay {
        RoundedRectangle(cornerRadius: PulseUI.cardRadius)
          .strokeBorder(PulseUI.separator, lineWidth: 1).allowsHitTesting(false)
      }
  }
}

struct PulseSwitchStyle: ToggleStyle {
  var showsLabel = true

  func makeBody(configuration: Configuration) -> some View {
    PulseToggleBody(configuration: configuration, kind: .switch, showsLabel: showsLabel)
  }
}

struct PulseCheckboxStyle: ToggleStyle {
  var showsLabel = true

  func makeBody(configuration: Configuration) -> some View {
    PulseToggleBody(configuration: configuration, kind: .checkbox, showsLabel: showsLabel)
  }
}

private struct PulseToggleBody: View {
  enum Kind { case `switch`, checkbox }

  let configuration: ToggleStyleConfiguration
  let kind: Kind
  let showsLabel: Bool
  @Environment(\.isEnabled) private var isEnabled
  @State private var hovered = false

  var body: some View {
    Button {
      withAnimation(.easeOut(duration: 0.14)) { configuration.isOn.toggle() }
    } label: {
      HStack(spacing: 10) {
        if kind == .checkbox { indicator }
        if showsLabel {
          configuration.label.frame(
            maxWidth: kind == .switch ? .infinity : nil, alignment: .leading)
        }
        if kind == .switch { indicator }
      }.frame(minWidth: 34, minHeight: 34).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .opacity(isEnabled ? 1 : 0.4)
    .onHover { hovered = $0 }
    .pulsePointingHand()
    .accessibilityRepresentation {
      Toggle(isOn: configuration.$isOn) { configuration.label }
    }
  }

  @ViewBuilder private var indicator: some View {
    let on = configuration.isOn
    switch kind {
    case .switch:
      Capsule().fill(on ? PulseUI.mint : hovered ? PulseUI.strongFill : PulseUI.selectedFill)
        .overlay(alignment: on ? .trailing : .leading) {
          Circle().fill(on ? Color.black.opacity(0.85) : PulseUI.primaryText)
            .frame(width: 16, height: 16).padding(3)
        }
        .frame(width: 38, height: 22)
    case .checkbox:
      RoundedRectangle(cornerRadius: 5)
        .fill(on ? PulseUI.mint : hovered ? PulseUI.hoverFill : PulseUI.controlFill)
        .overlay {
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(on ? .clear : PulseUI.strongStroke, lineWidth: 1)
        }
        .overlay {
          Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            .foregroundStyle(.black.opacity(0.85)).opacity(on ? 1 : 0)
        }
        .frame(width: 18, height: 18)
    }
  }
}
