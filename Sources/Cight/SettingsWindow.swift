import AppKit
import CightCore
import SwiftUI

@MainActor
final class SettingsWindow {
  private let model: SettingsModel
  private let notifier: Notifier
  private let launchAtLogin = LaunchAtLogin()
  private var window: NSWindow?

  init(model: SettingsModel, notifier: Notifier) {
    self.model = model
    self.notifier = notifier
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
    window.contentView = NSHostingView(
      rootView: SettingsView(model: model, notifier: notifier, launchAtLogin: launchAtLogin))
    window.center()
    return window
  }
}
