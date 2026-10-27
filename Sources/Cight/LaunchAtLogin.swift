import AppKit
import CightCore
import CryptoKit
import Foundation
import Observation
import ServiceManagement

enum AppInstance {
  @MainActor static var lock: InstanceLock?

  static var lockURL: URL {
    URL.applicationSupportDirectory.appending(path: "Cight/instance.lock")
  }
}

@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status: LoginItemStatus
  private(set) var error: String?

  nonisolated private static let settleTime: TimeInterval = 2

  @ObservationIgnored private let service = SMAppService.agent(plistName: LaunchAgent.plistName)

  init() {
    status = LaunchAtLogin.map(service.status)
  }

  var presentation: LoginItemPresentation {
    LoginItemPresentation(status: status)
  }

  func set(_ enabled: Bool) {
    Task { await enabled ? enable() : disable() }
  }

  private func enable() async {
    if await LaunchAtLogin.handOverToAgent(freshFirst: true) {
      error = nil
      refresh()
      NSApp.terminate(nil)
      return
    }
    refresh()
    error = "Cight could not start its background agent. Try again."
  }

  private func disable() async {
    if LaunchAgent.isStartedByAgent(arguments: CommandLine.arguments) {
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.createsNewApplicationInstance = true
      configuration.activates = false
      configuration.arguments = [LaunchAgent.waitArgument]
      do {
        _ = try await NSWorkspace.shared.openApplication(
          at: Bundle.main.bundleURL, configuration: configuration)
      } catch {
        self.error = "Could not disable launch at login: \(error.localizedDescription)"
        refresh()
        return
      }
    }
    do {
      try await service.unregister()
      error = nil
    } catch {
      self.error = "Could not disable launch at login: \(error.localizedDescription)"
    }
    refresh()
  }

  func refresh() {
    status = LaunchAtLogin.map(service.status)
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
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

  nonisolated static func registerFresh() throws {
    let service = SMAppService.agent(plistName: LaunchAgent.plistName)
    try? service.unregister()
    Thread.sleep(forTimeInterval: settleTime)
    try service.register()
  }

  static func handOverToAgent(freshFirst: Bool) async -> Bool {
    AppInstance.lock?.release()
    let started = await Task.detached { startAgent(freshFirst: freshFirst) }.value
    if !started {
      AppInstance.lock = InstanceLock.acquire(at: AppInstance.lockURL).lock
      if AppInstance.lock == nil { NSApp.terminate(nil) }
    }
    return started
  }

  nonisolated static func startAgent(freshFirst: Bool) -> Bool {
    for attempt in 0..<2 {
      if freshFirst && attempt == 0 { try? registerFresh() }
      _ = kickstart()
      let outcome = InstanceLock.waitForHolder(
        at: AppInstance.lockURL, timeout: StartupPlan.agentStartTimeout)
      guard outcome == .held else { continue }
      currentIdentity()?.save(to: .standard)
      return true
    }
    return false
  }

  nonisolated static func agentEnabled() -> Bool {
    SMAppService.agent(plistName: LaunchAgent.plistName).status == .enabled
  }

  static func isStale(defaults: UserDefaults) -> Bool {
    guard let current = currentIdentity() else { return false }
    return ReregisterPolicy.shouldReregister(
      agentEnabled: agentEnabled(), stored: AgentIdentity.load(from: defaults), current: current)
  }

  nonisolated static func kickstart() -> Bool {
    let process = Process()
    process.executableURL = URL(filePath: "/bin/launchctl")
    process.arguments = ["kickstart", "gui/\(getuid())/\(LaunchAgent.label)"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return false
    }
    process.waitUntilExit()
    return process.terminationStatus == 0
  }

  nonisolated private static func currentIdentity() -> AgentIdentity? {
    guard
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let url = Bundle.main.executableURL,
      let data = try? Data(contentsOf: url, options: .mappedIfSafe)
    else { return nil }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return AgentIdentity(version: version, binaryHash: digest)
  }
}
