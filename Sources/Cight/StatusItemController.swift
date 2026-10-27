import AppKit
import CightCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var shown: [MenuBarGlyph] = []
  var onClick: () -> Void = {}
  var onPointer: () -> Void = {}

  var frame: NSRect? {
    item.isVisible ? item.button?.window?.frame : nil
  }

  override init() {
    super.init()
    item.isVisible = false
    item.button?.target = self
    item.button?.action = #selector(clicked)
    item.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
    item.button?.addTrackingArea(
      NSTrackingArea(
        rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self, userInfo: nil))
  }

  func update(_ glyphs: [MenuBarGlyph]) {
    guard glyphs != shown else { return }
    shown = glyphs
    guard !glyphs.isEmpty else {
      item.isVisible = false
      return
    }
    item.isVisible = true
    let renderer = ImageRenderer(content: MenuBarStrip(glyphs: glyphs))
    renderer.scale = item.button?.window?.backingScaleFactor ?? 2
    let image = renderer.nsImage
    image?.isTemplate = false
    item.button?.image = image
  }

  @objc func mouseEntered(with event: NSEvent) {
    onPointer()
  }

  @objc func mouseExited(with event: NSEvent) {
    onPointer()
  }

  @objc private func clicked() {
    onClick()
  }
}
