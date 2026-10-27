import Foundation

public enum PollPolicy {
  private static let activeInterval: TimeInterval = 4
  private static let idleInterval: TimeInterval = 30
  private static let signedOutInterval: TimeInterval = 60
  private static let backoffBase: TimeInterval = 5
  private static let backoffCap: TimeInterval = 300
  private static let jitterShare = 0.25
  private static let rateLimitFloor: TimeInterval = 5

  public static func delay(
    after error: GitHubError?,
    failures: Int,
    panelVisible: Bool,
    hasActiveRun: Bool,
    wokeFromSleep: Bool,
    now: Date,
    jitter: Double
  ) -> TimeInterval {
    switch error {
    case .rateLimited(let resumeAt):
      return max(rateLimitFloor, resumeAt.timeIntervalSince(now))
    case _ where wokeFromSleep:
      return 0
    case nil:
      return panelVisible || hasActiveRun ? activeInterval : idleInterval
    case .unauthorized:
      return signedOutInterval
    case .notFound:
      return idleInterval
    case .transport, .server, .decoding:
      let base = min(backoffCap, backoffBase * pow(2, Double(max(0, failures - 1))))
      let spread = jitter.isFinite ? min(max(jitter, 0), 1) : 0
      return base * (1 + jitterShare * spread)
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
