import Foundation
import Testing

@testable import PeekCore

private func event(
  _ kind: RunEvent.Kind, name: String? = "Pull request", branch: String? = "fix",
  actor: String = "octocat", url: String? = "https://github.com/o/r/actions/runs/7", id: Int = 7,
  attempt: Int = 1, pull: Int? = nil
) -> RunEvent {
  var json: [String: Any] = [
    "id": id, "workflow_id": 1, "created_at": at(0).ISO8601Format(), "run_attempt": attempt,
    "actor": ["login": actor],
  ]
  json["name"] = name
  json["head_branch"] = branch
  json["html_url"] = url
  if let pull { json["pull_requests"] = [["number": pull]] }
  let data = try! JSONSerialization.data(withJSONObject: json)
  let run = try! JSONDecoder.github.decode(WorkflowRun.self, from: data)
  return RunEvent(kind: kind, repo: "o/r", run: run)
}

struct NotificationTests {
  @Test func defaultsAreOnForFailedAndFixedAndOffForStarted() {
    let settings = NotificationSettings()
    #expect(settings.failed)
    #expect(settings.fixed)
    #expect(!settings.started)
  }

  @Test func passedDefaultsToOn() {
    #expect(NotificationSettings().passed)
  }

  @Test func settingsStoredWithoutThePassedKeyReadAsOn() throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let stored = #"{"failed":false,"fixed":true,"started":true}"#
    defaults.set(Data(stored.utf8), forKey: NotificationSettings.key)
    let loaded = NotificationSettings.load(from: defaults)
    #expect(loaded == NotificationSettings(failed: false, fixed: true, started: true, passed: true))
  }

  @Test func thePassedToggleControlsOnlyThePassedKind() {
    let only = NotificationSettings(failed: false, fixed: false, started: false, passed: true)
    #expect(ToastContent.make(for: event(.passed), settings: only) != nil)
    #expect(ToastContent.make(for: event(.failed), settings: only) == nil)
    let off = NotificationSettings(failed: true, fixed: true, started: true, passed: false)
    #expect(ToastContent.make(for: event(.passed), settings: off) == nil)
  }

  @Test func aPassedToastReadsPassedOnTheBranchWithItsPullRequestNumber() throws {
    let toast = try #require(
      ToastContent.make(for: event(.passed, pull: 42), settings: NotificationSettings()))
    #expect(toast.glyph == .passed)
    #expect(toast.line2 == "Pull request passed on fix")
    #expect(toast.pullRequest == 42)
  }

  @Test func eachToggleControlsOnlyItsOwnEventKind() {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let none = NotificationSettings(failed: false, fixed: false, started: false)
    for kind in [RunEvent.Kind.failed, .recovered, .started] {
      #expect(ToastContent.make(for: event(kind), settings: all) != nil)
      #expect(ToastContent.make(for: event(kind), settings: none) == nil)
    }
    let onlyFailed = NotificationSettings(failed: true, fixed: false, started: false)
    #expect(ToastContent.make(for: event(.failed), settings: onlyFailed) != nil)
    #expect(ToastContent.make(for: event(.recovered), settings: onlyFailed) == nil)
    #expect(ToastContent.make(for: event(.started), settings: onlyFailed) == nil)
  }

  @Test func eachKindHasItsGlyphAndSecondLine() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let failed = try #require(ToastContent.make(for: event(.failed), settings: all))
    #expect(failed.glyph == .failed)
    #expect(failed.line1 == "o/r")
    #expect(failed.line2 == "Pull request failed on fix")
    let fixed = try #require(ToastContent.make(for: event(.recovered), settings: all))
    #expect(fixed.glyph == .passed)
    #expect(fixed.line2 == "Pull request fixed on fix")
    let started = try #require(ToastContent.make(for: event(.started), settings: all))
    #expect(started.glyph == .running)
    #expect(started.line2 == "Pull request started on fix")
  }

  @Test func carriesTheRunAddressAndPullRequestNumber() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let content = try #require(ToastContent.make(for: event(.failed), settings: all))
    #expect(content.url == URL(string: "https://github.com/o/r/actions/runs/7"))
    #expect(content.pullRequest == nil)
    let pull = try #require(ToastContent.make(for: event(.failed, pull: 123), settings: all))
    #expect(pull.pullRequest == 123)
  }

  @Test func fallsBackWhenFieldsAreMissingAndNeverNamesTheActor() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let sparse = try #require(
      ToastContent.make(for: event(.failed, name: nil, branch: nil, url: nil), settings: all))
    #expect(sparse.line2 == "Workflow failed on unknown")
    #expect(sparse.url == nil)
    #expect(!sparse.line2.contains("octocat"))
  }

  @Test func theSignedOutToastHasNoRunAddress() {
    let toast = ToastContent.signedOut
    #expect(toast.glyph == .signedOut)
    #expect(toast.line1 == "Signed out of GitHub")
    #expect(toast.line2 == "Run gh auth login in Terminal to resume monitoring.")
    #expect(toast.pullRequest == nil)
    #expect(toast.url == nil)
  }

  @Test func neverUsesEmDashesOrMiddleDots() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let banned: [Character] = ["\u{2014}", "\u{00B7}"]
    var texts = ToastContent.signedOut.line1 + ToastContent.signedOut.line2
    for kind in [RunEvent.Kind.failed, .recovered, .started] {
      let content = try #require(ToastContent.make(for: event(kind), settings: all))
      texts += content.line1 + content.line2
    }
    #expect(!texts.contains(where: banned.contains))
  }

  @Test func theStackPutsTheNewestFirstAndDropsTheOldestBeyondThree() {
    var stack: [Int] = []
    for value in 1...3 { stack = ToastStack.pushing(value, onto: stack) }
    #expect(stack == [3, 2, 1])
    stack = ToastStack.pushing(4, onto: stack)
    #expect(stack == [4, 3, 2])
  }

  @Test func settingsPersistAndFallBackToDefaultsWhenCorrupt() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    #expect(NotificationSettings.load(from: defaults) == NotificationSettings())
    let changed = NotificationSettings(failed: false, fixed: true, started: true)
    changed.save(to: defaults)
    #expect(NotificationSettings.load(from: defaults) == changed)
    defaults.set(Data([0xFF, 0x01]), forKey: NotificationSettings.key)
    #expect(NotificationSettings.load(from: defaults) == NotificationSettings())
  }
}
