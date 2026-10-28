import AppKit
import CightCore
import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
  private let notifier: Notifier
  private let updates: UpdateChecker
  private let launchAtLogin = LaunchAtLogin()
  private let recorder: ShortcutRecorder
  private let monitor: Monitor
  private var window: NSWindow?

  init(
    notifier: Notifier, updates: UpdateChecker, monitor: Monitor, shortcut: Shortcut,
    suspendShortcut: @escaping () -> Void, resumeShortcut: @escaping () -> Void,
    applyShortcut: @escaping (Shortcut) -> Bool
  ) {
    self.updates = updates
    self.notifier = notifier
    self.monitor = monitor
    recorder = ShortcutRecorder(
      shortcut: shortcut, suspend: suspendShortcut, resume: resumeShortcut, apply: applyShortcut)
    super.init()
  }

  func windowDidResignKey(_ notification: Notification) {
    recorder.cancel()
  }

  func windowWillClose(_ notification: Notification) {
    recorder.cancel()
  }

  func windowDidBecomeKey(_ notification: Notification) {
    launchAtLogin.refresh()
  }

  func show() {
    let window = self.window ?? makeWindow()
    self.window = window
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
      backing: .buffered, defer: false)
    window.title = "Cight Settings"
    window.appearance = NSAppearance(named: .darkAqua)
    window.isReleasedWhenClosed = false
    window.delegate = self
    let controller = NSHostingController(
      rootView: SettingsView(
        notifier: notifier, updates: updates, launchAtLogin: launchAtLogin, recorder: recorder,
        monitor: monitor))
    controller.sizingOptions = .preferredContentSize
    window.contentViewController = controller
    window.center()
    return window
  }
}
