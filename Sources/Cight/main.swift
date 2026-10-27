import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let monitor = Monitor()
  private var status: StatusItemController?
  private var panel: PanelController?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let status = StatusItemController()
    let panel = PanelController(monitor: monitor, anchor: { [weak status] in status?.frame })
    status.onClick = { [weak panel] in panel?.iconClicked() }
    status.onPointer = { [weak panel] in panel?.pointerMayHaveMoved() }
    track({ [monitor] in monitor.glyphs }, apply: { [weak status] in status?.update($0) })
    self.status = status
    self.panel = panel
    monitor.start()
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
