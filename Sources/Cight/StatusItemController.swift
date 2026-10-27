import AppKit
import CightCore
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
  private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var shown: [MenuBarGlyph] = []
  var onClick: () -> Void = {}

  var frame: NSRect? {
    item.isVisible ? item.button?.window?.frame : nil
  }

  override init() {
    super.init()
    item.isVisible = false
    item.button?.target = self
    item.button?.action = #selector(clicked)
    item.button?.sendAction(on: [.leftMouseDown])
  }

  func update(_ glyphs: [MenuBarGlyph]) {
    guard glyphs != shown else { return }
    shown = glyphs
    guard !glyphs.isEmpty else {
      item.isVisible = false
      return
    }
    let renderer = ImageRenderer(content: MenuBarStrip(glyphs: glyphs))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    let image = renderer.nsImage
    image?.isTemplate = false
    item.button?.image = image
    item.isVisible = true
  }

  @objc private func clicked() {
    onClick()
  }
}
