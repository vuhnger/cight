import AppKit
import CightCore
import Observation
import SwiftUI

final class ToastPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

struct ToastItem: Identifiable {
  let id = UUID()
  let content: ToastContent
  var fading = false
}

@MainActor
@Observable
final class ToastModel {
  var items: [ToastItem] = []
}

@MainActor
final class ToastController {
  private static let lifetime: Duration = .seconds(6)
  private static let fade: Duration = .milliseconds(250)

  private let model = ToastModel()
  private let anchor: () -> NSRect?
  private let panel: ToastPanel
  private let hosting: NSHostingView<ToastStackView>
  private var timers: [UUID: Task<Void, Never>] = [:]
  private var panelOpen = false

  init(anchor: @escaping () -> NSRect?) {
    self.anchor = anchor
    hosting = NSHostingView(
      rootView: ToastStackView(model: model, hover: { _, _ in }, tap: { _ in }))
    hosting.sizingOptions = []
    panel = ToastPanel(
      contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered,
      defer: false)
    panel.contentView = hosting
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.appearance = NSAppearance(named: .darkAqua)
    hosting.rootView = ToastStackView(
      model: model,
      hover: { [weak self] id, inside in self?.hover(id, inside: inside) },
      tap: { [weak self] id in self?.tap(id) })
    track({ [model] in model.items.map(\.id) }, apply: { [weak self] _ in self?.layout() })
  }

  func show(_ content: ToastContent) -> Bool {
    guard !panelOpen else { return false }
    let item = ToastItem(content: content)
    let kept = ToastStack.pushing(item.id, onto: model.items.map(\.id))
    for id in timers.keys where !kept.contains(id) { cancelTimer(id) }
    model.items = ([item] + model.items).filter { kept.contains($0.id) }
    startTimer(item.id)
    return true
  }

  func panelVisibilityChanged(_ visible: Bool) {
    panelOpen = visible
    guard visible else { return }
    for id in Array(timers.keys) { cancelTimer(id) }
    model.items = []
  }

  private func startTimer(_ id: UUID) {
    timers[id]?.cancel()
    timers[id] = Task { [weak self] in
      try? await Task.sleep(for: Self.lifetime)
      guard !Task.isCancelled else { return }
      self?.fadeOut(id)
    }
  }

  private func cancelTimer(_ id: UUID) {
    timers[id]?.cancel()
    timers[id] = nil
  }

  private func fadeOut(_ id: UUID) {
    timers[id] = nil
    guard let index = model.items.firstIndex(where: { $0.id == id }) else { return }
    withAnimation(.easeOut(duration: 0.25)) { model.items[index].fading = true }
    Task { [weak self] in
      try? await Task.sleep(for: Self.fade)
      self?.remove(id)
    }
  }

  private func remove(_ id: UUID) {
    cancelTimer(id)
    model.items.removeAll { $0.id == id }
  }

  private func hover(_ id: UUID, inside: Bool) {
    guard model.items.contains(where: { $0.id == id && !$0.fading }) else { return }
    if inside { cancelTimer(id) } else { startTimer(id) }
  }

  private func tap(_ id: UUID) {
    if let url = model.items.first(where: { $0.id == id })?.content.url {
      NSWorkspace.shared.open(url)
    }
    remove(id)
  }

  private func layout() {
    guard !model.items.isEmpty else {
      panel.orderOut(nil)
      return
    }
    hosting.layoutSubtreeIfNeeded()
    let size = hosting.fittingSize
    let screens = NSScreen.screens.map {
      PanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
    }
    let flush = PanelPlacement.Insets(leading: 0, trailing: 0, top: 0)
    let origin: CGPoint
    if let icon = anchor(),
      let placed = PanelPlacement.origin(
        icon: icon, screens: screens, insets: flush, panelSize: size)
    {
      origin = placed
    } else {
      let screen = NSScreen.main?.visibleFrame ?? .zero
      origin = CGPoint(
        x: screen.maxX - size.width - PanelPlacement.margin,
        y: screen.maxY - PanelPlacement.gap - size.height)
    }
    panel.setFrame(NSRect(origin: origin, size: size), display: true)
    panel.orderFrontRegardless()
  }
}

struct ToastStackView: View {
  let model: ToastModel
  let hover: (UUID, Bool) -> Void
  let tap: (UUID) -> Void

  var body: some View {
    GlassEffectContainer(spacing: 12) {
      VStack(spacing: 8) {
        ForEach(model.items) { item in
          ToastCard(content: item.content)
            .opacity(item.fading ? 0 : 1)
            .contentShape(Rectangle())
            .onHover { hover(item.id, $0) }
            .onTapGesture { tap(item.id) }
        }
      }
    }
    .fixedSize()
    .preferredColorScheme(.dark)
  }
}

struct ToastCard: View {
  let content: ToastContent

  var body: some View {
    HStack(spacing: 12) {
      StateGlyph(kind: glyph, size: 20)
      VStack(alignment: .leading, spacing: 2) {
        header
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(content.line2).font(.callout).foregroundStyle(.secondary)
            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
          if let number = content.pullRequest {
            Text("#\(number)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Metrics.cardHorizontal)
    .padding(.vertical, Metrics.cardVertical)
    .frame(width: Metrics.toastWidth, alignment: .leading)
    .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
  }

  @ViewBuilder private var header: some View {
    if let slash = content.line1.firstIndex(of: "/") {
      HStack(spacing: 0) {
        Text(content.line1[...slash]).foregroundStyle(.secondary)
        Text(content.line1[content.line1.index(after: slash)...]).fontWeight(.semibold)
      }
      .lineLimit(1)
    } else {
      Text(content.line1).fontWeight(.semibold).lineLimit(1)
    }
  }

  private var glyph: GlyphKind {
    switch content.glyph {
    case .passed: .passed
    case .failed: .failed
    case .running: .running(nil)
    case .signedOut: .signedOut
    }
  }
}
