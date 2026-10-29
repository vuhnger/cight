import AppKit
import PeekCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var shown: MenuBarGlyph?
  var onClick: () -> Void = {}
  var onMenu: (Bool) -> Void = { _ in }
  var onSettings: () -> Void = {}
  var onCheck: () -> Void = {}
  var onRefresh: () -> Void = {}
  var onFeedback: () -> Void = {}
  var canCheck: () -> Bool = { false }

  var frame: NSRect? {
    item.button?.window?.frame
  }

  override init() {
    super.init()
    item.isVisible = true
    item.button?.target = self
    item.button?.action = #selector(clicked)
    item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
  }

  func update(_ glyph: MenuBarGlyph) {
    guard glyph != shown else { return }
    shown = glyph
    if glyph == .idle {
      item.button?.image = Self.idleImage
      return
    }
    let renderer = ImageRenderer(content: MenuBarIcon(glyph: glyph))
    renderer.scale = item.button?.window?.backingScaleFactor ?? 2
    let image = renderer.nsImage
    image?.isTemplate = false
    item.button?.image = image
  }

  private static let idleImage: NSImage = {
    let size = NSSize(width: 18, height: 18)
    let image = NSImage(size: size, flipped: false) { rect in
      let line = 2.2
      let radius = 7.0 - line / 2
      let path = NSBezierPath()
      path.appendArc(
        withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: radius,
        startAngle: 90, endAngle: -180, clockwise: true)
      path.lineWidth = line
      path.lineCapStyle = .round
      NSColor.black.setStroke()
      path.stroke()
      return true
    }
    image.isTemplate = true
    return image
  }()

  @objc private func clicked() {
    guard let event = NSApp.currentEvent else { return onClick() }
    if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
      showMenu()
    } else {
      onClick()
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    menu.autoenablesItems = false
    let settings = NSMenuItem(
      title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
    let check = NSMenuItem(
      title: "Check for updates…", action: #selector(checkForUpdates), keyEquivalent: "")
    let refresh = NSMenuItem(title: "Refresh now", action: #selector(refreshNow), keyEquivalent: "")
    let feedback = NSMenuItem(
      title: "Send feedback…", action: #selector(sendFeedback), keyEquivalent: "")
    for entry in [settings, check, refresh, feedback] { entry.target = self }
    check.isEnabled = canCheck()
    menu.items = [
      settings, check, refresh, feedback, .separator(),
      NSMenuItem(
        title: "Quit Peek", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
    ]
    onMenu(true)
    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
    onMenu(false)
  }

  @objc private func openSettings() { onSettings() }
  @objc private func checkForUpdates() { onCheck() }
  @objc private func refreshNow() { onRefresh() }
  @objc private func sendFeedback() { onFeedback() }
}
