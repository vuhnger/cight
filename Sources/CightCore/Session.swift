import Foundation

public enum SessionState: Sendable, Equatable {
  case unknown
  case signedOut
  case signedIn
}

public enum SessionPolicy {
  public static func sample(signedOutSignal: Bool, anySuccess: Bool) -> SessionState {
    if signedOutSignal { return .signedOut }
    return anySuccess ? .signedIn : .unknown
  }
}

public struct SignOutGate {
  private static let key = "signOutNotified"
  private static let required = 2

  private let defaults: UserDefaults
  private var consecutive = 0
  private var notified: Bool

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    notified = defaults.bool(forKey: Self.key)
  }

  public mutating func shouldNotify(_ state: SessionState) -> Bool {
    switch state {
    case .signedIn:
      consecutive = 0
      setNotified(false)
      return false
    case .unknown:
      return false
    case .signedOut:
      consecutive += 1
      return consecutive >= Self.required && !notified
    }
  }

  public mutating func didPost() {
    setNotified(true)
  }

  private mutating func setNotified(_ value: Bool) {
    guard notified != value else { return }
    notified = value
    defaults.set(value, forKey: Self.key)
  }
}
