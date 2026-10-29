import AppKit
import OSLog
import PeekCore
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
  private var toasts: ToastController?

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
    status.onMenu = { [weak panel] in panel?.menuChanged(open: $0) }
    status.onRefresh = { [monitor] in monitor.retry() }
    status.onFeedback = {
      let info = Bundle.main.infoDictionary
      NSWorkspace.shared.open(
        Feedback.url(
          appVersion: info?["CFBundleShortVersionString"] as? String ?? "",
          build: info?["CFBundleVersion"] as? String ?? "",
          system: ProcessInfo.processInfo.operatingSystemVersion))
    }
    track({ [monitor] in monitor.menuBarGlyph }, apply: { [weak status] in status?.update($0) })
    self.status = status
    self.panel = panel

    let toasts = ToastController(anchor: { [weak status] in status?.frame })
    panel.onVisibilityChange = { [weak toasts] in toasts?.panelVisibilityChanged($0) }
    let notifier = Notifier(defaults: .standard, show: { toasts.show($0) })
    monitor.onEvents = { notifier.deliver($0) }
    monitor.onSession = { notifier.observe($0) }
    monitor.onGitLabSession = { notifier.observeGitLab($0) }
    self.toasts = toasts
    self.notifier = notifier

    let updates = UpdateChecker(controller: updater)
    let window = SettingsWindow(
      notifier: notifier, updates: updates, monitor: monitor, shortcut: panel.shortcut,
      suspendShortcut: { [weak panel] in panel?.suspendHotKey() },
      resumeShortcut: { [weak panel] in panel?.resumeHotKey() },
      applyShortcut: { [weak panel] in panel?.setShortcut($0) ?? false })
    settingsWindow = window
    status.onSettings = { [weak window] in window?.show() }
    status.onCheck = { [updates] in updates.check() }
    status.canCheck = { [updates] in updates.canCheck }
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
