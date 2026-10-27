import Foundation

public enum PollPolicy {
  private static let activeInterval: TimeInterval = 4
  private static let idleInterval: TimeInterval = 30
  private static let signedOutInterval: TimeInterval = 60
  private static let backoffBase: TimeInterval = 5
  private static let backoffCap: TimeInterval = 300
  private static let jitterShare = 0.25

  public static func delay(
    after error: GitHubError?,
    failures: Int,
    panelVisible: Bool,
    hasActiveRun: Bool,
    wokeFromSleep: Bool,
    now: Date,
    jitter: Double
  ) -> TimeInterval {
    if case .rateLimited(let resumeAt) = error {
      return max(0, resumeAt.timeIntervalSince(now))
    }
    if wokeFromSleep { return 0 }
    switch error {
    case nil:
      return panelVisible || hasActiveRun ? activeInterval : idleInterval
    case .unauthorized:
      return signedOutInterval
    case .notFound:
      return idleInterval
    case .transport, .server, .decoding:
      let base = backoffBase * pow(2, Double(max(0, failures - 1)))
      return min(backoffCap, base * (1 + jitterShare * jitter))
    case .rateLimited:
      return 0
    }
  }

  public static func failures(after error: GitHubError?, previous: Int) -> Int {
    switch error {
    case nil: 0
    case .transport, .server, .decoding: previous + 1
    default: previous
    }
  }
}
