import CightCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLogin {
  private(set) var status: SMAppService.Status
  private(set) var error: String?

  private let service = SMAppService.agent(plistName: LaunchAgent.plistName)

  init() {
    status = service.status
  }

  var isEnabled: Bool {
    status == .enabled || status == .requiresApproval
  }

  var needsApproval: Bool {
    status == .requiresApproval
  }

  func set(_ enabled: Bool) {
    do {
      if enabled {
        try service.register()
      } else {
        try service.unregister()
      }
      error = nil
    } catch {
      self.error =
        "Could not \(enabled ? "enable" : "disable") launch at login: \(error.localizedDescription)"
    }
    status = service.status
  }
}
