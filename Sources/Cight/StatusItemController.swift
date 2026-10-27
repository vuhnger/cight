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
    item.button?.window?.frame
  }

  override init() {
    super.init()
    item.isVisible = true
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
    if glyphs == [.idle] {
      item.button?.image = Self.idleImage
      return
    }
    let renderer = ImageRenderer(content: MenuBarStrip(glyphs: glyphs))
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
