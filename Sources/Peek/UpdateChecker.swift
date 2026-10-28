import Observation
import Sparkle

@MainActor @Observable
final class UpdateChecker {
  private(set) var canCheck = false
  @ObservationIgnored private let controller: SPUStandardUpdaterController
  @ObservationIgnored private var observation: NSKeyValueObservation?

  init(controller: SPUStandardUpdaterController) {
    self.controller = controller
    canCheck = controller.updater.canCheckForUpdates
    observation = controller.updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
      let allowed = updater.canCheckForUpdates
      Task { @MainActor in self?.canCheck = allowed }
    }
  }

  func check() {
    controller.checkForUpdates(nil)
  }
}
