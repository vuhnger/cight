import AppKit
import CightCore
import CryptoKit
import Foundation
import Observation
import ServiceManagement

enum LaunchAgent {
  static let label = "com.vuhnger.cight.agent"
  static let plistName = "\(label).plist"
  static let argument = "--launch-agent"
  static let waitArgument = "--wait-for-lock"

  @MainActor static var lock: InstanceLock?

  static var lockURL: URL {
    URL.applicationSupportDirectory.appending(path: "Cight/instance.lock")
  }

  static var service: SMAppService { SMAppService.agent(plistName: plistName) }

  static func has(_ flag: String) -> Bool { CommandLine.arguments.dropFirst().contains(flag) }

  static func isEnabled() -> Bool { service.status == .enabled }

  static func isStale(defaults: UserDefaults) -> Bool {
    guard let current = identity() else { return false }
    return ReregisterPolicy.shouldReregister(
      agentEnabled: isEnabled(), stored: AgentIdentity.load(from: defaults), current: current)
  }

  static func start(fresh: Bool) -> Bool {
    for attempt in 0..<2 {
      if fresh && attempt == 0 {
        try? service.unregister()
        Thread.sleep(forTimeInterval: 2)
        try? service.register()
      }
      kickstart()
      guard InstanceLock.waitForHolder(at: lockURL, timeout: 5) == .held else { continue }
      identity()?.save(to: .standard)
      return true
    }
    return false
  }

  private static func kickstart() {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/launchctl")
    process.arguments = ["kickstart", "gui/\(getuid())/\(label)"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
  }

  private static func identity() -> AgentIdentity? {
    guard
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let url = Bundle.main.executableURL,
      let data = try? Data(contentsOf: url, options: .mappedIfSafe)
    else { return nil }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return AgentIdentity(version: version, binaryHash: digest)
  }
}

@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status = LaunchAtLogin.map(LaunchAgent.service.status)
  private(set) var error: String?

  var presentation: LoginItemPresentation { LoginItemPresentation(status: status) }

  func set(_ enabled: Bool) {
    Task { await enabled ? enable() : disable() }
  }

  func refresh() {
    status = LaunchAtLogin.map(LaunchAgent.service.status)
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func enable() async {
    LaunchAgent.lock?.release()
    let started = await Task.detached { LaunchAgent.start(fresh: true) }.value
    refresh()
    if started {
      error = nil
      NSApp.terminate(nil)
      return
    }
    LaunchAgent.lock = InstanceLock.acquire(at: LaunchAgent.lockURL).lock
    if LaunchAgent.lock == nil { NSApp.terminate(nil) }
    error = "Cight could not start its background agent. Try again."
  }

  private func disable() async {
    if LaunchAgent.has(LaunchAgent.argument) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      configuration.activates = false
      configuration.arguments = [LaunchAgent.waitArgument]
      do {
        _ = try await NSWorkspace.shared.openApplication(
          at: Bundle.main.bundleURL, configuration: configuration)
      } catch {
        self.error = "Could not disable launch at login: \(error.localizedDescription)"
        return
      }
    }
    do {
      try await LaunchAgent.service.unregister()
      error = nil
    } catch {
      self.error = "Could not disable launch at login: \(error.localizedDescription)"
    }
    refresh()
  }

  private static func map(_ status: SMAppService.Status) -> LoginItemStatus {
    switch status {
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notFound: .notFound
    case .notRegistered: .notRegistered
    @unknown default: .notRegistered
    }
  }
}
