import Foundation

public enum PanelNotice: Sendable, Equatable {
  case ghMissing
  case signedOut
  case noRecentRuns
  case rateLimited(until: Date)
  case offline(since: Date?)
  case unavailable(since: Date?)
}

public enum NoticePolicy {
  public static func notice(
    ghInstalled: Bool, tokenAvailable: Bool, repoCount: Int, errors: [GitHubError],
    lastUpdated: Date?
  ) -> PanelNotice? {
    if !ghInstalled { return .ghMissing }
    if !tokenAvailable || errors.contains(.unauthorized) { return .signedOut }
    let resumes = errors.compactMap { error -> Date? in
      if case .rateLimited(let date) = error { date } else { nil }
    }
    if let latest = resumes.max() { return .rateLimited(until: latest) }
    if errors.contains(where: { if case .transport = $0 { true } else { false } }) {
      return .offline(since: lastUpdated)
    }
    if errors.contains(where: { $0 != .notFound }) { return .unavailable(since: lastUpdated) }
    return repoCount == 0 ? .noRecentRuns : nil
  }
}
