import AppKit
import CightCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let monitor = Monitor()
  private var status: StatusItemController?
  private var panel: PanelController?
  private var settingsWindow: SettingsWindow?
  private var notifier: Notifier?
  private var settingsModel: SettingsModel?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.appearance = NSAppearance(named: .darkAqua)
    let status = StatusItemController()
    let panel = PanelController(monitor: monitor, anchor: { [weak status] in status?.frame })
    status.onClick = { [weak panel] in panel?.iconClicked() }
    status.onPointer = { [weak panel] in panel?.pointerMayHaveMoved() }
    track({ [monitor] in monitor.glyphs }, apply: { [weak status] in status?.update($0) })
    self.status = status
    self.panel = panel

    let notifier = Notifier(defaults: .standard, center: SystemNotificationCenter.make())
    let model = SettingsModel(monitor: monitor)
    monitor.onEvents = { events in Task { await notifier.deliver(events) } }
    monitor.onSession = { state in
      Task {
        await notifier.observe(state)
        await model.sessionChanged(state)
      }
    }
    self.notifier = notifier
    self.settingsModel = model

    let window = SettingsWindow(model: model, notifier: notifier)
    settingsWindow = window
    monitor.start()

    if monitor.watched.isEmpty { window.show() }
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
    -> Bool
  {
    settingsWindow?.show()
    return true
  }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
