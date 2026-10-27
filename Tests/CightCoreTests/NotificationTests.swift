import Foundation
import Testing

@testable import CightCore

private func event(
  _ kind: RunEvent.Kind, name: String? = "Pull request", branch: String? = "fix",
  actor: String = "octocat", url: String? = "https://github.com/o/r/actions/runs/7", id: Int = 7,
  attempt: Int = 1
) -> RunEvent {
  var json: [String: Any] = [
    "id": id, "workflow_id": 1, "created_at": at(0).ISO8601Format(), "run_attempt": attempt,
    "actor": ["login": actor],
  ]
  json["name"] = name
  json["head_branch"] = branch
  json["html_url"] = url
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

  @Test func eachToggleControlsOnlyItsOwnEventKind() {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let none = NotificationSettings(failed: false, fixed: false, started: false)
    for kind in [RunEvent.Kind.failed, .recovered, .started] {
      #expect(NotificationContent.make(for: event(kind), settings: all) != nil)
      #expect(NotificationContent.make(for: event(kind), settings: none) == nil)
    }
    let onlyFailed = NotificationSettings(failed: true, fixed: false, started: false)
    #expect(NotificationContent.make(for: event(.failed), settings: onlyFailed) != nil)
    #expect(NotificationContent.make(for: event(.recovered), settings: onlyFailed) == nil)
    #expect(NotificationContent.make(for: event(.started), settings: onlyFailed) == nil)
  }

  @Test func namesTheKindRepoWorkflowBranchAndActor() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let failed = try #require(NotificationContent.make(for: event(.failed), settings: all))
    #expect(failed.title == "Failed in o/r")
    #expect(failed.body == "Pull request on fix by octocat")
    let fixed = try #require(NotificationContent.make(for: event(.recovered), settings: all))
    #expect(fixed.title == "Fixed in o/r")
    let started = try #require(NotificationContent.make(for: event(.started), settings: all))
    #expect(started.title == "Started in o/r")
  }

  @Test func carriesTheRunAddressForTheClick() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let content = try #require(NotificationContent.make(for: event(.failed), settings: all))
    #expect(content.url == URL(string: "https://github.com/o/r/actions/runs/7"))
  }

  @Test func stripsTheBotSuffixAndFallsBackWhenFieldsAreMissing() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let bot = try #require(
      NotificationContent.make(for: event(.failed, actor: "dependabot[bot]"), settings: all))
    #expect(bot.body.hasSuffix("by dependabot"))
    let sparse = try #require(
      NotificationContent.make(for: event(.failed, name: nil, branch: nil, url: nil), settings: all)
    )
    #expect(sparse.body == "Workflow on unknown by octocat")
    #expect(sparse.url == nil)
  }

  @Test func identifiersDifferPerRunAttemptAndKind() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let ids = try [
      event(.failed), event(.failed, attempt: 2), event(.recovered), event(.failed, id: 8),
    ].map { try #require(NotificationContent.make(for: $0, settings: all)).identifier }
    #expect(Set(ids).count == 4)
  }

  @Test func neverUsesEmDashesOrMiddleDots() throws {
    let all = NotificationSettings(failed: true, fixed: true, started: true)
    let banned: [Character] = ["\u{2014}", "\u{00B7}"]
    var texts = NotificationContent.signedOut.title + NotificationContent.signedOut.body
    for kind in [RunEvent.Kind.failed, .recovered, .started] {
      let content = try #require(NotificationContent.make(for: event(kind), settings: all))
      texts += content.title + content.body
    }
    #expect(!texts.contains(where: banned.contains))
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

  @Test func signedOutNoticeFiresOnlyOnTheTransition() {
    var gate = SignOutGate()
    let sequence = [false, true, true, true, false, true]
    let fired = sequence.map { gate.shouldNotify(signedOut: $0) }
    #expect(fired == [false, true, false, false, false, true])
  }

  @Test func aLaunchWhileSignedOutNotifiesOnce() {
    var gate = SignOutGate()
    let fired = [true, true].map { gate.shouldNotify(signedOut: $0) }
    #expect(fired == [true, false])
  }
}
