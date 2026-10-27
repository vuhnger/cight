import AppKit
import CightCore

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
  private var tookOverFromPlainInstance = false
  private var quitObserver: (any NSObjectProtocol)?

  private var startedByAgent: Bool { LaunchAgent.isStartedByAgent(arguments: arguments) }

  private static var lockURL: URL {
    URL.applicationSupportDirectory.appending(path: "Cight/instance.lock")
  }

  func applicationWillFinishLaunching(_ notification: Notification) {
    let first = InstanceLock.acquire(at: Self.lockURL)
    switch StartupPlan.decide(
      lockAcquired: first != nil, startedByAgent: startedByAgent,
      waitsForLock: LaunchAgent.waitsForLock(arguments: arguments))
    {
    case .run:
      lock = first
    case .exit:
      exit(0)
    case .takeOver(let askHolderToQuit):
      lock = waitForLock(askingHolder: askHolderToQuit)
      guard lock != nil else { exit(0) }
      tookOverFromPlainInstance = askHolderToQuit
    }
  }

  private func waitForLock(askingHolder: Bool) -> InstanceLock? {
    let attempts = Int(HandoverPolicy.takeOverTimeout)
    for _ in 0..<attempts {
      if askingHolder {
        DistributedNotificationCenter.default().postNotificationName(
          Notification.Name(HandoverPolicy.quitRequest), object: nil, userInfo: nil,
          deliverImmediately: true)
      }
      if let acquired = InstanceLock.acquire(at: Self.lockURL, timeout: 1) { return acquired }
    }
    return nil
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
    track(
      { [monitor] in monitor.session },
      apply: { state in
        Task {
          await notifier.observe(state)
          await model.sessionChanged(state)
        }
      })
    self.notifier = notifier
    self.settingsModel = model

    let window = SettingsWindow(model: model, notifier: notifier)
    settingsWindow = window
    monitor.start()

    quitObserver = DistributedNotificationCenter.default().addObserver(
      forName: Notification.Name(HandoverPolicy.quitRequest), object: nil, queue: .main
    ) { [startedByAgent] _ in
      if HandoverPolicy.holderShouldYield(startedByAgent: startedByAgent) {
        MainActor.assumeIsolated { NSApp.terminate(nil) }
      }
    }

    if tookOverFromPlainInstance
      || SettingsLaunchPolicy.shouldOpen(
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
