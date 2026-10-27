import AppKit
import CightCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let monitor = Monitor()
  private var status: StatusItemController?
  private var panel: PanelController?
  private var settingsWindow: SettingsWindow?
  private var notifier: Notifier?

  func applicationWillFinishLaunching(_ notification: Notification) {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    if let other = running.first(where: { $0.processIdentifier != getpid() }) {
      other.activate()
      exit(0)
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

    let notifier = Notifier(defaults: .standard)
    monitor.onEvents = { [weak notifier] in notifier?.deliver($0) }
    track(
      { [monitor] in monitor.notice == .signedOut },
      apply: { [weak notifier] in notifier?.observe(signedOut: $0) })
    self.notifier = notifier

    let window = SettingsWindow(
      model: SettingsModel(
        monitor: monitor, client: GitHubClient(tokenProvider: { await GhTokenReader.read() })),
      notifier: notifier)
    settingsWindow = window
    monitor.start()

    let startedByAgent = LaunchAgent.isStartedByAgent(arguments: CommandLine.arguments)
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
