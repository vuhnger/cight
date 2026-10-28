import CightCore
import Foundation
import Observation

@MainActor
@Observable
final class Notifier {
  var settings: NotificationSettings {
    didSet { settings.save(to: defaults) }
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let show: (ToastContent) -> Bool
  @ObservationIgnored private var signOutGate: SignOutGate
  @ObservationIgnored private var gitLabSignOutGate: SignOutGate

  init(defaults: UserDefaults, show: @escaping (ToastContent) -> Bool) {
    self.defaults = defaults
    self.show = show
    signOutGate = SignOutGate(defaults: defaults)
    gitLabSignOutGate = SignOutGate(defaults: defaults, key: SignOutGate.gitLabKey)
    settings = NotificationSettings.load(from: defaults)
  }

  func deliver(_ events: [RunEvent]) {
    for event in events {
      if let content = ToastContent.make(for: event, settings: settings) {
        _ = show(content)
      }
    }
  }

  func observe(_ state: SessionState) {
    if signOutGate.shouldNotify(state), show(.signedOut) {
      signOutGate.didPost()
    }
  }
}

extension Notifier {
  func observeGitLab(_ state: SessionState) {
    if gitLabSignOutGate.shouldNotify(state), show(.gitLabSignedOut) {
      gitLabSignOutGate.didPost()
    }
  }
}
