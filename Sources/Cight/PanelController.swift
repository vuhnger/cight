import AppKit
import Carbon.HIToolbox
import CightCore
import OSLog
import Observation
import SwiftUI

final class GlassPanel: NSPanel {
  var onCancel: () -> Void = {}

  override var canBecomeKey: Bool { true }

  override func cancelOperation(_ sender: Any?) { onCancel() }
}

@MainActor
func track<Value>(
  _ read: @escaping @MainActor () -> Value, apply: @escaping @MainActor (Value) -> Void
) {
  let value = withObservationTracking {
    read()
  } onChange: {
    Task { @MainActor in track(read, apply: apply) }
  }
  apply(value)
}

@MainActor
final class PanelController: NSObject {
  private static let signposter = OSSignposter(subsystem: "com.vuhnger.cight", category: "panel")
  private static let log = Logger(subsystem: "com.vuhnger.cight", category: "panel")
  private static var shared: PanelController?

  private let monitor: Monitor
  private let anchor: () -> NSRect?
  private let panel: GlassPanel
  var onVisibilityChange: (Bool) -> Void = { _ in }
  private var machine = PanelMachine()
  private var timer: Task<Void, Never>?
  private var outsideClicks: Any?
  private var pointerMonitors: [Any] = []
  private var trigger: (name: String, start: CFTimeInterval)?
  private var interval: OSSignpostIntervalState?
  private var hotKey: EventHotKeyRef?

  init(monitor: Monitor, anchor: @escaping () -> NSRect?) {
    self.monitor = monitor
    self.anchor = anchor
    panel = GlassPanel(
      contentRect: NSRect(x: 0, y: 0, width: Metrics.panelWidth, height: 100),
      styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
    super.init()
    let hosting = NSHostingView(
      rootView: PanelRoot(monitor: monitor, open: { [weak self] url in self?.openRun(url) })
        .environment(\.controlActiveState, .key))
    hosting.sizingOptions = []
    panel.contentView = hosting
    panel.isFloatingPanel = true
    panel.level = .popUpMenu
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.onCancel = { [weak self] in self?.send(.escape) }
    track({ Metrics.height(of: monitor) }, apply: { [weak self] _ in self?.resize() })
    warmUp()
    watchPointer()
    registerHotKey()
  }

  func iconClicked() {
    trigger = ("click", NSApp.currentEvent?.timestamp ?? CACurrentMediaTime())
    send(.iconClick)
  }

  private func hotKeyPressed(at start: CFTimeInterval) {
    trigger = ("hotkey", start)
    send(.hotkey)
  }

  private func openRun(_ url: URL) {
    NSWorkspace.shared.open(url)
    send(.dismiss)
  }

  private func send(_ input: PanelInput) {
    if case .timer = input {
      samplePointer()
      if machine.phase == .opening { trigger = ("hover", CACurrentMediaTime()) }
    }
    for effect in machine.handle(input) {
      switch effect {
      case .show(let pinned): show(pinned: pinned)
      case .hide: hide()
      case .cancelTimer: timer?.cancel()
      case .schedule(let scheduled):
        timer?.cancel()
        timer = Task { [weak self] in
          try? await Task.sleep(for: .seconds(scheduled.delay))
          guard !Task.isCancelled else { return }
          self?.send(.timer(scheduled))
        }
      }
    }
  }

  private func warmUp() {
    resize()
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    panel.contentView?.layoutSubtreeIfNeeded()
    panel.displayIfNeeded()
    panel.orderOut(nil)
    panel.alphaValue = 1
  }

  private func show(pinned: Bool) {
    if !panel.isVisible {
      resize()
      position()
      interval = Self.signposter.beginInterval("open", id: Self.signposter.makeSignpostID())
      panel.orderFrontRegardless()
      watchOutsideClicks()
      monitor.panelVisibilityChanged(true)
      onVisibilityChange(true)
      measureFirstFrame()
    }
    if pinned { panel.makeKey() }
  }

  private func hide() {
    timer?.cancel()
    panel.orderOut(nil)
    if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
    outsideClicks = nil
    monitor.panelVisibilityChanged(false)
    onVisibilityChange(false)
  }

  private func measureFirstFrame() {
    guard let view = panel.contentView, let started = trigger else { return }
    trigger = nil
    let link = view.displayLink(target: self, selector: #selector(frameTick(_:)))
    pendingFrame = started
    link.add(to: .main, forMode: .common)
  }

  private var pendingFrame: (name: String, start: CFTimeInterval)?

  @objc private func frameTick(_ link: CADisplayLink) {
    link.invalidate()
    guard let pending = pendingFrame else { return }
    pendingFrame = nil
    if let interval { Self.signposter.endInterval("open", interval) }
    interval = nil
    let milliseconds = (link.targetTimestamp - pending.start) * 1000
    Self.log.notice(
      "first frame \(pending.name, privacy: .public) \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms"
    )
  }

  private func screenFrame() -> NSRect {
    (NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main)?
      .visibleFrame ?? .zero
  }

  private func resize() {
    let screen = screenFrame()
    let cap = max(120, screen.height - 16)
    let height = min(Metrics.height(of: monitor), cap)
    let frame = panel.frame
    guard abs(frame.height - height) > 0.5 else { return }
    panel.setFrame(
      NSRect(x: frame.minX, y: frame.maxY - height, width: Metrics.panelWidth, height: height),
      display: false)
  }

  private func position() {
    let size = panel.frame.size
    let inset = Metrics.outerPadding
    let screens = NSScreen.screens.map {
      PanelPlacement.Screen(frame: $0.frame, visibleFrame: $0.visibleFrame)
    }
    if let icon = anchor(),
      let origin = PanelPlacement.origin(
        icon: icon, screens: screens,
        insets: PanelPlacement.Insets(leading: inset, trailing: inset, top: inset),
        panelSize: size)
    {
      panel.setFrame(NSRect(origin: origin, size: size), display: false)
      return
    }
    let screen = NSScreen.main?.visibleFrame ?? screenFrame()
    panel.setFrame(
      NSRect(
        x: screen.maxX - size.width - PanelPlacement.margin + inset,
        y: screen.maxY - PanelPlacement.gap + inset - size.height, width: size.width,
        height: size.height), display: false)
  }

  private func watchOutsideClicks() {
    guard outsideClicks == nil else { return }
    outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] _ in
      MainActor.assumeIsolated { self?.send(.outsideClick) }
    }
  }

  private func watchPointer() {
    pointerMonitors = [
      NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
        MainActor.assumeIsolated { self?.samplePointer() }
      },
      NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
        MainActor.assumeIsolated { self?.samplePointer() }
        return event
      },
    ].compactMap { $0 }
  }

  private func samplePointer() {
    let location = NSEvent.mouseLocation
    let overIcon = anchor().map { Self.contains($0, location) } ?? false
    let overPanel = panel.isVisible && Self.contains(panel.frame, location)
    send(.pointer(overIcon: overIcon, overPanel: overPanel))
  }

  private static func contains(_ rect: NSRect, _ point: NSPoint) -> Bool {
    point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
  }

  private func registerHotKey() {
    Self.shared = self
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, _ in
        let start = GetEventTime(event)
        MainActor.assumeIsolated { PanelController.shared?.hotKeyPressed(at: start) }
        return noErr
      }, 1, &spec, nil, nil)
    RegisterEventHotKey(
      UInt32(kVK_ANSI_G), UInt32(cmdKey | optionKey | controlKey),
      EventHotKeyID(signature: OSType(0x4349_4748), id: 1), GetApplicationEventTarget(), 0,
      &hotKey)
  }
}
