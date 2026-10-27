import Foundation

public enum SessionState: Sendable, Equatable {
  case unknown
  case signedOut
  case signedIn
}

public enum SessionPolicy {
  public static func next(
    current: SessionState, signedOutSignal: Bool, anySuccess: Bool
  ) -> SessionState {
    if signedOutSignal { return .signedOut }
    if anySuccess { return .signedIn }
    return current
  }
}

public struct SignOutGate: Sendable {
  private var notified = false

  public init() {}

  public mutating func shouldNotify(_ state: SessionState) -> Bool {
    switch state {
    case .signedIn:
      notified = false
      return false
    case .unknown:
      return false
    case .signedOut:
      defer { notified = true }
      return !notified
    }
  }
}

public enum LoginItemStatus: Sendable, Equatable {
  case enabled
  case requiresApproval
  case notRegistered
  case notFound
}

public struct LoginItemPresentation: Sendable, Equatable {
  public let isOn: Bool
  public let message: String?
  public let offersSystemSettings: Bool

  public init(status: LoginItemStatus) {
    isOn = status == .enabled
    offersSystemSettings = status == .requiresApproval
    message =
      switch status {
      case .requiresApproval: "Approve Cight under Login Items in System Settings to finish."
      case .notFound: "Cight cannot find its login item. Reinstall the app."
      case .enabled, .notRegistered: nil
      }
  }
}
