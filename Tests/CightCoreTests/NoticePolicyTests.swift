import Foundation
import Testing

@testable import CightCore

private func notice(
  gh: Bool = true, token: Bool = true, repos: Int = 2, errors: [GitHubError] = [],
  updated: Date? = at(0)
) -> PanelNotice? {
  NoticePolicy.notice(
    ghInstalled: gh, tokenAvailable: token, repoCount: repos, errors: errors,
    lastUpdated: updated)
}

struct NoticePolicyTests {
  @Test func healthyStateHasNoNotice() {
    #expect(notice() == nil)
  }

  @Test func repositoryNotFoundStaysInsideItsCard() {
    #expect(notice(errors: [.notFound, .notFound]) == nil)
  }

  @Test func missingGhWinsOverEverything() {
    #expect(notice(gh: false, token: false, repos: 0, errors: [.unauthorized]) == .ghMissing)
  }

  @Test func noTokenOrUnauthorizedMeansSignedOut() {
    #expect(notice(token: false) == .signedOut)
    #expect(notice(errors: [.notFound, .unauthorized, .transport(.timedOut)]) == .signedOut)
  }

  @Test func noRunsInTheWindowIsReportedWhenSignedIn() {
    #expect(notice(repos: 0) == .noRecentRuns)
    #expect(notice(token: false, repos: 0) == .signedOut)
  }

  @Test func aFailedDiscoveryWithNoListShowsTheErrorNotTheEmptyState() {
    #expect(notice(repos: 0, errors: [.transport(.timedOut)]) == .offline(since: at(0)))
    #expect(notice(repos: 0, errors: [.server(500)]) == .unavailable(since: at(0)))
  }

  @Test func rateLimitUsesTheLatestResumeDate() {
    #expect(
      notice(errors: [.rateLimited(resumeAt: at(60)), .rateLimited(resumeAt: at(300))])
        == .rateLimited(until: at(300)))
  }

  @Test func rateLimitBeatsOffline() {
    #expect(
      notice(errors: [.transport(.notConnectedToInternet), .rateLimited(resumeAt: at(60))])
        == .rateLimited(until: at(60)))
  }

  @Test func transportErrorsMeanOfflineWithTheAgeOfTheData() {
    #expect(notice(errors: [.transport(.notConnectedToInternet)]) == .offline(since: at(0)))
    #expect(
      notice(errors: [.server(502), .transport(.timedOut)], updated: nil)
        == .offline(since: nil))
  }

  @Test func serverAndDecodingErrorsMeanUnavailable() {
    #expect(notice(errors: [.server(503)]) == .unavailable(since: at(0)))
    #expect(notice(errors: [.decoding]) == .unavailable(since: at(0)))
  }
}
