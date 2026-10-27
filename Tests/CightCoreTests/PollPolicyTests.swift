import Foundation
import Testing

@testable import CightCore

private func delay(
  after error: GitHubError?,
  failures: Int = 0,
  panelVisible: Bool = false,
  hasActiveRun: Bool = false,
  wokeFromSleep: Bool = false,
  jitter: Double = 0
) -> TimeInterval {
  PollPolicy.delay(
    after: error, failures: failures, panelVisible: panelVisible, hasActiveRun: hasActiveRun,
    wokeFromSleep: wokeFromSleep, now: t0, jitter: jitter)
}

struct PollPolicyTests {
  @Test func pollsEveryFourSecondsWhilePanelIsVisibleOrARunIsActive() {
    #expect(delay(after: nil, panelVisible: true) == 4)
    #expect(delay(after: nil, hasActiveRun: true) == 4)
  }

  @Test func pollsEveryThirtySecondsWhenIdle() {
    #expect(delay(after: nil) == 30)
  }

  @Test func backsOffExponentiallyFromFiveSecondsToTheCap() {
    let schedule = (1...9).map { delay(after: .transport(.timedOut), failures: $0) }
    #expect(schedule == [5, 10, 20, 40, 80, 160, 300, 300, 300])
  }

  @Test func addsUpToTwentyFivePercentJitter() {
    #expect(delay(after: .server(500), failures: 1, jitter: 1) == 6.25)
    #expect(delay(after: .server(500), failures: 1, jitter: 0.5) == 5.625)
  }

  @Test func jitterStillSpreadsRetriesAtTheCap() {
    #expect(delay(after: .server(500), failures: 30, jitter: 0) == 300)
    #expect(delay(after: .server(500), failures: 30, jitter: 0.5) == 337.5)
    #expect(delay(after: .server(500), failures: 30, jitter: 1) == 375)
  }

  @Test func clampsJitterToTheUnitInterval() {
    #expect(delay(after: .server(500), failures: 1, jitter: 7) == 6.25)
    #expect(delay(after: .server(500), failures: 1, jitter: -3) == 5)
    #expect(delay(after: .server(500), failures: 1, jitter: .nan) == 5)
  }

  @Test func transportServerAndDecodingErrorsAllBackOff() {
    let errors: [GitHubError] = [.transport(.notConnectedToInternet), .server(503), .decoding]
    for error in errors {
      #expect(delay(after: error, failures: 2, panelVisible: true) == 10)
    }
  }

  @Test func failureCountResetsOnSuccessAndGrowsOnBackoffErrors() {
    #expect(PollPolicy.failures(after: nil, previous: 5) == 0)
    #expect(PollPolicy.failures(after: .transport(.timedOut), previous: 2) == 3)
    #expect(PollPolicy.failures(after: .server(500), previous: 0) == 1)
    #expect(PollPolicy.failures(after: .rateLimited(resumeAt: at(10)), previous: 2) == 2)
  }

  @Test func waitsUntilTheRateLimitResumeDate() {
    #expect(delay(after: .rateLimited(resumeAt: at(90)), panelVisible: true) == 90)
  }

  @Test func neverPollsFasterThanTheFloorWhileRateLimited() {
    #expect(delay(after: .rateLimited(resumeAt: at(-5))) == 5)
    #expect(delay(after: .rateLimited(resumeAt: at(0))) == 5)
    #expect(delay(after: .rateLimited(resumeAt: at(2))) == 5)
    #expect(delay(after: .rateLimited(resumeAt: at(-600)), wokeFromSleep: true) == 5)
  }

  @Test func signedOutChecksEverySixtySeconds() {
    #expect(delay(after: .unauthorized, panelVisible: true) == 60)
    #expect(delay(after: .unauthorized, hasActiveRun: true) == 60)
  }

  @Test func notFoundDoesNotHammerTheServer() {
    #expect(delay(after: .notFound, panelVisible: true) == 30)
  }

  @Test func wakeFromSleepPollsImmediately() {
    #expect(delay(after: nil, wokeFromSleep: true) == 0)
    #expect(delay(after: .transport(.timedOut), failures: 4, wokeFromSleep: true) == 0)
    #expect(delay(after: .unauthorized, wokeFromSleep: true) == 0)
  }

  @Test func wakeFromSleepStillRespectsARateLimit() {
    #expect(delay(after: .rateLimited(resumeAt: at(90)), wokeFromSleep: true) == 90)
  }

  @Test func aForcedPollNeverOverridesARateLimitOrABackoff() {
    #expect(!PollPolicy.allowsForcedPoll(after: .rateLimited(resumeAt: t0)))
    #expect(!PollPolicy.allowsForcedPoll(after: .transport(.timedOut)))
    #expect(!PollPolicy.allowsForcedPoll(after: .server(502)))
    #expect(!PollPolicy.allowsForcedPoll(after: .decoding))
  }

  @Test func aForcedPollIsAllowedWhenHealthySignedOutOrWhenARepoIsGone() {
    #expect(PollPolicy.allowsForcedPoll(after: nil))
    #expect(PollPolicy.allowsForcedPoll(after: .unauthorized))
    #expect(PollPolicy.allowsForcedPoll(after: .notFound))
  }
}
