import Foundation
import Testing

@testable import CightCore

struct SessionTests {
  @Test func signedOutNotifiesOncePerEpisodeEvenAcrossOfflinePolls() {
    var gate = SignOutGate()
    let states: [SessionState] = [.signedOut, .unknown, .signedOut]
    #expect(states.map { gate.shouldNotify($0) } == [true, false, false])
  }

  @Test func onlyASuccessfulPollStartsANewEpisode() {
    var gate = SignOutGate()
    let states: [SessionState] = [.signedOut, .unknown, .signedIn, .unknown, .signedOut]
    #expect(states.map { gate.shouldNotify($0) } == [true, false, false, false, true])
  }

  @Test func aLaunchWhileSignedOutNotifiesOnce() {
    var gate = SignOutGate()
    #expect([SessionState.signedOut, .signedOut].map { gate.shouldNotify($0) } == [true, false])
  }

  @Test func unauthorizedBeatsSuccessfulRepos() {
    #expect(
      SessionPolicy.next(current: .signedIn, signedOutSignal: true, anySuccess: true)
        == .signedOut)
  }

  @Test func successSignsIn() {
    #expect(
      SessionPolicy.next(current: .signedOut, signedOutSignal: false, anySuccess: true)
        == .signedIn)
  }

  @Test func offlineOrRateLimitedKeepsTheCurrentState() {
    for current in [SessionState.unknown, .signedIn, .signedOut] {
      #expect(
        SessionPolicy.next(current: current, signedOutSignal: false, anySuccess: false)
          == current)
    }
  }
}

struct LoginItemTests {
  @Test func onlyEnabledCountsAsOn() {
    #expect(LoginItemPresentation(status: .enabled).isOn)
    #expect(!LoginItemPresentation(status: .requiresApproval).isOn)
    #expect(!LoginItemPresentation(status: .notRegistered).isOn)
    #expect(!LoginItemPresentation(status: .notFound).isOn)
  }

  @Test func approvalOffersTheSystemSettingsButton() {
    let approval = LoginItemPresentation(status: .requiresApproval)
    #expect(approval.offersSystemSettings)
    #expect(approval.message?.contains("Login Items") == true)
    #expect(!LoginItemPresentation(status: .enabled).offersSystemSettings)
  }

  @Test func notFoundHasItsOwnMessage() {
    let missing = LoginItemPresentation(status: .notFound)
    let approval = LoginItemPresentation(status: .requiresApproval)
    #expect(missing.message != nil)
    #expect(missing.message != approval.message)
    #expect(!missing.offersSystemSettings)
    #expect(LoginItemPresentation(status: .enabled).message == nil)
  }
}
