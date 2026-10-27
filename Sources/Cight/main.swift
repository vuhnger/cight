import AppKit
import CightCore
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let arguments = CommandLine.arguments
  private let monitor = Monitor()
  private var status: StatusItemController?
  private var panel: PanelController?
  private var settingsWindow: SettingsWindow?
  private var notifier: Notifier?
  private var settingsModel: SettingsModel?
  private var lock: InstanceLock?
  private let log = Logger(subsystem: "com.vuhnger.cight", category: "startup")

  private var startedByAgent: Bool { LaunchAgent.isStartedByAgent(arguments: arguments) }

  private static var lockURL: URL {
    URL.applicationSupportDirectory.appending(path: "Cight/instance.lock")
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    let waits = LaunchAgent.waitsForLock(arguments: arguments)
    let plain = !startedByAgent && !waits
    let attempt = InstanceLock.acquire(at: Self.lockURL)
    if plain { LaunchAtLogin.reregisterIfStale(defaults: .standard) }
    switch StartupPlan.decide(
      lock: attempt.outcome, startedByAgent: startedByAgent, waitsForLock: waits,
      agentEnabled: plain && LaunchAtLogin.agentEnabled())
    {
    case .run:
      lock = attempt.lock
    case .waitForLock:
      lock = InstanceLock.acquire(at: Self.lockURL, timeout: StartupPlan.waitTimeout).lock
      if lock == nil {
        log.error("Gave up waiting for the instance lock")
        exit(1)
      }
    case .kickstartThenExit:
      if LaunchAtLogin.kickstart() { exit(0) }
      log.error("Could not start the launch agent")
      guard let fallback = attempt.lock else { exit(0) }
      lock = fallback
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

    if SettingsLaunchPolicy.shouldOpen(
      startedByLaunchAgent: startedByAgent, watchedCount: monitor.watched.count)
    {
      window.show()
    }
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
