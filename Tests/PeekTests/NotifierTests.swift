import Foundation
import Testing

@testable import Peek
@testable import PeekCore

@MainActor
private final class Shown {
  var accepts = true
  private(set) var contents: [ToastContent] = []

  func show(_ content: ToastContent) -> Bool {
    guard accepts else { return false }
    contents.append(content)
    return true
  }
}

@MainActor
struct NotifierTests {
  private func make(_ shown: Shown, defaults: UserDefaults = freshDefaults()) -> Notifier {
    Notifier(defaults: defaults, show: { shown.show($0) })
  }

  @Test func theSignedOutToastWaitsForASecondSignedOutResult() {
    let shown = Shown()
    let notifier = make(shown)
    notifier.observe(.signedOut)
    #expect(shown.contents.isEmpty)
    notifier.observe(.signedOut)
    #expect(shown.contents == [.signedOut])
  }

  @Test func aDroppedSignedOutToastIsShownLater() {
    let shown = Shown()
    shown.accepts = false
    let notifier = make(shown)
    notifier.observe(.signedOut)
    notifier.observe(.signedOut)
    shown.accepts = true
    notifier.observe(.signedOut)
    #expect(shown.contents.count == 1)
    notifier.observe(.signedOut)
    #expect(shown.contents.count == 1)
  }

  @Test func theSignedOutToastIsShownOncePerEpisode() {
    let shown = Shown()
    let notifier = make(shown)
    for state in [SessionState.signedOut, .signedOut, .unknown, .signedOut] {
      notifier.observe(state)
    }
    #expect(shown.contents.count == 1)
    for state in [SessionState.signedIn, .signedOut, .signedOut] {
      notifier.observe(state)
    }
    #expect(shown.contents.count == 2)
  }

  @Test func aRestartDuringAnEpisodeDoesNotShowAgain() {
    let defaults = freshDefaults()
    let shown = Shown()
    let first = make(shown, defaults: defaults)
    first.observe(.signedOut)
    first.observe(.signedOut)
    let second = make(shown, defaults: defaults)
    second.observe(.signedOut)
    second.observe(.signedOut)
    #expect(shown.contents.count == 1)
  }

  @Test func runEventsFollowTheSettings() {
    let shown = Shown()
    let notifier = make(shown)
    notifier.deliver([failedEvent()])
    #expect(shown.contents.count == 1)
    notifier.settings.failed = false
    notifier.deliver([failedEvent()])
    #expect(shown.contents.count == 1)
  }
}
