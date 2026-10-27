import AppKit
import CightCore
import OSLog
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let log = Logger(subsystem: "com.vuhnger.cight", category: "startup")
  private let monitor = Monitor()
  private let updater = SPUStandardUpdaterController(
    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
  private var status: StatusItemController?
  private var panel: PanelController?
  private var settingsWindow: SettingsWindow?
  private var notifier: Notifier?

  private func others() -> [NSRunningApplication] {
    guard let id = Bundle.main.bundleIdentifier else { return [] }
    let me = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication.runningApplications(withBundleIdentifier: id)
      .filter { $0.processIdentifier != me }
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    let me = ProcessInfo.processInfo.processIdentifier
    let byLaunchd = LaunchAgent.byLaunchd
    switch StartupPlan.decide(
      me: me, others: others().map(\.processIdentifier), byLaunchd: byLaunchd,
      agentLoaded: !byLaunchd && LaunchAgent.isLoaded())
    {
    case .run:
      LaunchAgent.repairPath()
    case .kickstart:
      if LaunchAgent.kickstart() { exit(0) }
      log.error("Could not kickstart the launch agent, running without it")
    case .yield:
      others().first?.activate()
      exit(0)
    case .waitForOthers:
      for _ in 0..<30 where !others().isEmpty { usleep(100_000) }
      if !others().isEmpty {
        log.error("Another instance is still running")
        exit(1)
      }
      LaunchAgent.repairPath()
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
    monitor.onEvents = { events in Task { await notifier.deliver(events) } }
    monitor.onSession = { state in Task { await notifier.observe(state) } }
    self.notifier = notifier

    let window = SettingsWindow(notifier: notifier, updates: UpdateChecker(controller: updater))
    settingsWindow = window
    monitor.start()

    if !LaunchAgent.byLaunchd { window.show() }
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
