import AppKit
import CightCore
import SwiftUI

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
  private let notifier: Notifier
  private let updates: UpdateChecker
  private let launchAtLogin = LaunchAtLogin()
  private var window: NSWindow?

  init(notifier: Notifier, updates: UpdateChecker) {
    self.updates = updates
    self.notifier = notifier
    super.init()
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
      rootView: SettingsView(notifier: notifier, updates: updates, launchAtLogin: launchAtLogin))
    controller.sizingOptions = .preferredContentSize
    window.contentViewController = controller
    window.center()
    return window
  }
}
