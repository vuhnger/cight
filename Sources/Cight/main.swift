import AppKit
import CightCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let log = Logger(subsystem: "com.vuhnger.cight", category: "startup")
  private let monitor = Monitor()
  private var status: StatusItemController?
  private var panel: PanelController?
  private var settingsWindow: SettingsWindow?
  private var notifier: Notifier?
  private var settingsModel: SettingsModel?

  func applicationWillFinishLaunching(_ notification: Notification) {
    let waits = LaunchAgent.has(LaunchAgent.argument) || LaunchAgent.has(LaunchAgent.waitArgument)
    let attempt = InstanceLock.acquire(at: LaunchAgent.lockURL)
    switch StartupPlan.decide(
      lock: attempt.outcome, waits: waits, agentEnabled: !waits && LaunchAgent.isEnabled())
    {
    case .run:
      LaunchAgent.lock = attempt.lock
    case .waitForLock:
      LaunchAgent.lock = InstanceLock.acquire(at: LaunchAgent.lockURL, timeout: 10).lock
      if LaunchAgent.lock == nil {
        log.error("Gave up waiting for the instance lock")
        exit(1)
      }
    case .kickstartThenExit:
      attempt.lock?.release()
      if LaunchAgent.start(fresh: LaunchAgent.isStale(defaults: .standard)) { exit(0) }
      log.error("The launch agent did not start, running without it")
      LaunchAgent.lock = InstanceLock.acquire(at: LaunchAgent.lockURL).lock
      if LaunchAgent.lock == nil { exit(0) }
    case .exitQuietly:
      exit(0)
    case .exitFailure:
      log.error("Could not open the instance lock file")
      exit(1)
    }
  }

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

    if !LaunchAgent.has(LaunchAgent.argument) || monitor.watched.isEmpty { window.show() }
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
