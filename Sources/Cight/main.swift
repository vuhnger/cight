import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem?

  func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.image = NSImage(
      systemSymbolName: "checkmark.circle", accessibilityDescription: "Cight")
    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(
        title: "Quit Cight", action: #selector(NSApplication.terminate(_:)),
        keyEquivalent: "q"))
    item.menu = menu
    statusItem = item
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
