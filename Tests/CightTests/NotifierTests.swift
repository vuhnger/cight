import Testing
import UserNotifications

@testable import Cight
@testable import CightCore

@MainActor
struct NotifierTests {
  private func signedOutTwice(_ notifier: Notifier) async {
    await notifier.observe(.signedOut)
    await notifier.observe(.signedOut)
  }

  @Test func theSignedOutNoticeNeverTriggersThePermissionPrompt() async {
    let center = FakeCenter(status: .notDetermined)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await signedOutTwice(notifier)
    #expect(center.requests == 0)
    #expect(center.added.isEmpty)
  }

  @Test func theSignedOutNoticeIsSkippedWhenNotificationsAreDenied() async {
    let center = FakeCenter(status: .denied)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await signedOutTwice(notifier)
    #expect(center.requests == 0)
    #expect(center.added.isEmpty)
  }

  @Test func aSkippedNoticeIsPostedLaterOnceNotificationsAreAllowed() async {
    let center = FakeCenter(status: .denied)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await signedOutTwice(notifier)
    center.status = .authorized
    await notifier.observe(.signedOut)
    #expect(center.added.count == 1)
    await notifier.observe(.signedOut)
    #expect(center.added.count == 1)
  }

  @Test func theSignedOutNoticeWaitsForASecondSignedOutResult() async {
    let center = FakeCenter(status: .authorized)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await notifier.observe(.signedOut)
    #expect(center.added.isEmpty)
    await notifier.observe(.signedOut)
    #expect(center.added.count == 1)
  }

  @Test func theSignedOutNoticeIsPostedOncePerEpisode() async {
    let center = FakeCenter(status: .authorized)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    for state in [SessionState.signedOut, .signedOut, .unknown, .signedOut] {
      await notifier.observe(state)
    }
    #expect(center.added.count == 1)
    for state in [SessionState.signedIn, .signedOut, .signedOut] {
      await notifier.observe(state)
    }
    #expect(center.added.count == 2)
  }

  @Test func aRestartDuringAnEpisodeDoesNotNotifyAgain() async {
    let defaults = freshDefaults()
    let center = FakeCenter(status: .authorized)
    let first = Notifier(defaults: defaults, center: center)
    await signedOutTwice(first)
    let second = Notifier(defaults: defaults, center: center)
    await signedOutTwice(second)
    await second.observe(.signedOut)
    #expect(center.added.count == 1)
  }

  @Test func runEventsAskForPermissionWhenItIsStillUndecided() async {
    let center = FakeCenter(status: .notDetermined)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await notifier.deliver([failedEvent()])
    #expect(center.requests == 1)
    #expect(center.added.count == 1)
  }

  @Test func runEventsAreDroppedWhenPermissionIsRefused() async {
    let center = FakeCenter(status: .notDetermined, grantsOnRequest: false)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await notifier.deliver([failedEvent()])
    #expect(center.added.isEmpty)
  }

  @Test func disabledKindsArePostedNever() async {
    let center = FakeCenter(status: .authorized)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    notifier.settings.failed = false
    await notifier.deliver([failedEvent()])
    #expect(center.added.isEmpty)
  }

  @Test func refreshingPicksUpAChangeMadeInSystemSettings() async {
    let center = FakeCenter(status: .denied)
    let notifier = Notifier(defaults: freshDefaults(), center: center)
    await notifier.refreshAuthorization()
    #expect(!notifier.isAllowed)
    center.status = .authorized
    await notifier.refreshAuthorization()
    #expect(notifier.isAllowed)
  }

  @Test func withoutACenterNothingHappensAndNothingCrashes() async {
    let notifier = Notifier(defaults: freshDefaults(), center: nil)
    await notifier.observe(.signedOut)
    await notifier.deliver([failedEvent()])
    await notifier.refreshAuthorization()
    #expect(!notifier.isAllowed)
  }
}
