import AppKit
import CightCore
import CryptoKit
import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status: LoginItemStatus
  private(set) var error: String?

  @ObservationIgnored private let service = SMAppService.agent(plistName: LaunchAgent.plistName)

  init() {
    status = LaunchAtLogin.map(service.status)
  }

  var presentation: LoginItemPresentation {
    LoginItemPresentation(status: status)
  }

  func set(_ enabled: Bool) {
    if enabled {
      enable()
    } else {
      Task { await disable() }
    }
  }

  private func enable() {
    do {
      try service.register()
      error = nil
      LaunchAtLogin.currentIdentity()?.save(to: .standard)
    } catch {
      self.error = "Could not enable launch at login: \(error.localizedDescription)"
    }
    refresh()
    if status == .enabled, !LaunchAgent.isStartedByAgent(arguments: CommandLine.arguments) {
      NSApp.terminate(nil)
    }
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

  static func agentEnabled() -> Bool {
    SMAppService.agent(plistName: LaunchAgent.plistName).status == .enabled
  }

  static func reregisterIfStale(defaults: UserDefaults) {
    guard let current = currentIdentity() else { return }
    let service = SMAppService.agent(plistName: LaunchAgent.plistName)
    guard
      ReregisterPolicy.shouldReregister(
        agentEnabled: service.status == .enabled, stored: AgentIdentity.load(from: defaults),
        current: current)
    else { return }
    try? service.unregister()
    try? service.register()
    current.save(to: defaults)
  }

  static func kickstart() -> Bool {
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

  private static func currentIdentity() -> AgentIdentity? {
    guard
      let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
      let url = Bundle.main.executableURL,
      let data = try? Data(contentsOf: url, options: .mappedIfSafe)
    else { return nil }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return AgentIdentity(version: version, binaryHash: digest)
  }
}
