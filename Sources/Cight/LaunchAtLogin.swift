import AppKit
import CightCore
import Observation

enum LaunchAgent {
  static var plistURL: URL {
    URL.homeDirectory.appending(path: "Library/LaunchAgents/\(LaunchAgentPlist.label).plist")
  }

  static var service: String { "gui/\(getuid())/\(LaunchAgentPlist.label)" }

  static var executable: String { Bundle.main.executablePath ?? CommandLine.arguments[0] }

  static var byLaunchd: Bool {
    CommandLine.arguments.dropFirst().contains(LaunchAgentPlist.argument)
  }

  static func isLoaded() -> Bool {
    run("/bin/launchctl", ["print", service]) == 0
  }

  static func kickstart() -> Bool {
    run("/bin/launchctl", ["kickstart", service]) == 0
  }

  static func enable() -> Bool {
    do {
      try FileManager.default.createDirectory(
        at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try LaunchAgentPlist.render(program: executable).write(to: plistURL, options: .atomic)
    } catch {
      return false
    }
    if run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistURL.path]) == 0 { return true }
    try? FileManager.default.removeItem(at: plistURL)
    return false
  }

  static func disable() -> Bool {
    if byLaunchd {
      let script = #"launchctl bootout "$1"; rm -f "$2"; open -n "$3""#
      let args = ["-c", script, "sh", service, plistURL.path, Bundle.main.bundleURL.path]
      return (try? Process.run(URL(filePath: "/bin/sh"), arguments: args)) != nil
    }
    let unloaded = !isLoaded() || run("/bin/launchctl", ["bootout", service]) == 0
    if unloaded { try? FileManager.default.removeItem(at: plistURL) }
    return unloaded
  }

  static func repairPath() {
    guard let data = try? Data(contentsOf: plistURL),
      LaunchAgentPlist.program(in: data) != executable
    else { return }
    try? LaunchAgentPlist.render(program: executable).write(to: plistURL, options: .atomic)
  }

  private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(filePath: tool)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
  }
}

@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var isOn = LaunchAgent.isLoaded()
  private(set) var busy = false
  private(set) var error: String?

  func refresh() {
    Task { isOn = await Task.detached { LaunchAgent.isLoaded() }.value }
  }

  func set(_ enabled: Bool) {
    guard !busy else { return }
    busy = true
    Task {
      let ok = await Task.detached { enabled ? LaunchAgent.enable() : LaunchAgent.disable() }.value
      isOn = await Task.detached { LaunchAgent.isLoaded() }.value
      busy = false
      guard ok else {
        error = "Could not turn launch at login \(enabled ? "on" : "off")."
        return
      }
      error = nil
      if enabled { NSApp.terminate(nil) }
    }
  }
}
