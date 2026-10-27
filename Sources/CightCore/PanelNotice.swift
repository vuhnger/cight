import Foundation

public enum PanelNotice: Sendable, Equatable {
  case ghMissing
  case signedOut
  case nothingWatched
  case rateLimited(until: Date)
  case offline(since: Date?)
  case unavailable(since: Date?)
}

public enum NoticePolicy {
  public static func notice(
    ghInstalled: Bool, tokenAvailable: Bool, watchedCount: Int, errors: [GitHubError],
    lastUpdated: Date?
  ) -> PanelNotice? {
    nil
  }
}
