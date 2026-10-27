import AppKit
import CightCore
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
    do {
      if enabled {
        try service.register()
      } else {
        if LaunchAgent.isStartedByAgent(arguments: CommandLine.arguments) {
          startWaitingCopy()
        }
        try service.unregister()
      }
      error = nil
    } catch {
      self.error =
        "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
    }
    status = LaunchAtLogin.map(service.status)
  }

  func refresh() {
    status = LaunchAtLogin.map(service.status)
  }

  func openSystemSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }

  private func startWaitingCopy() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    configuration.activates = false
    configuration.arguments = [LaunchAgent.waitArgument]
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
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
