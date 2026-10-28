import Foundation
import Testing

@testable import PeekCore

struct SessionTests {
  private func gate() -> (SignOutGate, UserDefaults) {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    return (SignOutGate(defaults: defaults), defaults)
  }

  private func run(_ gate: inout SignOutGate, _ states: [SessionState]) -> [Bool] {
    states.map { gate.shouldNotify($0) }
  }

  @Test func needsTwoConsecutiveSignedOutResults() {
    var (gate, _) = gate()
    #expect(run(&gate, [.signedOut, .signedOut]) == [false, true])
  }

  @Test func anOfflinePollBetweenDoesNotCountAsRecovery() {
    var (gate, _) = gate()
    #expect(run(&gate, [.signedOut, .unknown, .signedOut]) == [false, false, true])
  }

  @Test func aSuccessfulPollBetweenRestartsTheCount() {
    var (gate, _) = gate()
    #expect(run(&gate, [.signedOut, .signedIn, .signedOut]) == [false, false, false])
  }

  @Test func keepsAskingUntilAPostActuallyHappens() {
    var (gate, _) = gate()
    #expect(run(&gate, [.signedOut, .signedOut, .signedOut]) == [false, true, true])
    gate.didPost()
    #expect(run(&gate, [.signedOut, .unknown, .signedOut]) == [false, false, false])
  }

  @Test func anEpisodeSurvivesARestart() {
    var (first, defaults) = gate()
    _ = run(&first, [.signedOut, .signedOut])
    first.didPost()
    var second = SignOutGate(defaults: defaults)
    #expect(run(&second, [.signedOut, .signedOut, .signedOut]) == [false, false, false])
  }

  @Test func aSuccessfulPollEndsTheEpisodeAcrossRestarts() {
    var (first, defaults) = gate()
    _ = run(&first, [.signedOut, .signedOut])
    first.didPost()
    _ = first.shouldNotify(.signedIn)
    var second = SignOutGate(defaults: defaults)
    #expect(run(&second, [.signedOut, .signedOut]) == [false, true])
  }

  @Test func unauthorizedBeatsSuccessfulRepos() {
    #expect(SessionPolicy.sample(signedOutSignal: true, anySuccess: true) == .signedOut)
  }

  @Test func successSignsIn() {
    #expect(SessionPolicy.sample(signedOutSignal: false, anySuccess: true) == .signedIn)
  }

  @Test func offlineOrRateLimitedSaysNothing() {
    #expect(SessionPolicy.sample(signedOutSignal: false, anySuccess: false) == .unknown)
  }
}
