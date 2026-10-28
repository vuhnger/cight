import Foundation
import Testing

@testable import PeekCore

struct ModelsTests {
  @Test func decodesRecordedRunsFixture() throws {
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Fixture.data("runs"))
    #expect(page.runs.count == 10)
    let first = page.runs[0]
    #expect(first.id == 40_536_524_302)
    #expect(first.state == .failed)
    #expect(first.headBranch == "replace-with-reusable-cmake-build-workflow")
    #expect(first.headRepository?.fullName == "kkebo/swift-format")
    let rerun = try #require(page.runs.first { $0.runAttempt == 2 })
    #expect(rerun.actor?.login == "owenv")
    #expect(rerun.triggeringActor?.login == "rintaro")
  }

  @Test func decodesCommitTitleAndStarterAvatar() throws {
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Fixture.data("runs"))
    let first = page.runs[0]
    #expect(first.displayTitle == "Replace cmake-smoke-test with reusable CMake build workflow")
    #expect(first.actor?.avatarUrl == "https://avatars.githubusercontent.com/u/601636?v=4")
    #expect(page.runs[1].displayTitle == nil)
  }

  @Test func decodesRecordedRepoUserAndRepoList() throws {
    let repos = try JSONDecoder.github.decode([Repo].self, from: Fixture.data("repos"))
    #expect(repos.map(\.name) == ["llvm-project", "swift", "swift-corelibs-foundation"])
    #expect(repos[0].defaultBranch == "next")
    #expect(
      repos.map(\.pushedAt) == [
        Date(timeIntervalSince1970: 1_793_125_285), Date(timeIntervalSince1970: 1_793_124_397),
        Date(timeIntervalSince1970: 1_793_122_748),
      ])
    let viewer = try JSONDecoder.github.decode(Viewer.self, from: Fixture.data("user"))
    #expect(viewer.login == "octocat")
  }

  @Test func unknownStatusAndConclusionDecodeAsNeutral() throws {
    let json = """
      {"id": 1, "workflow_id": 2, "created_at": "2023-11-14T22:13:20Z",
       "status": "frobnicating", "conclusion": "exploded"}
      """
    let run = try JSONDecoder.github.decode(WorkflowRun.self, from: Data(json.utf8))
    #expect(run.state == .neutral)
  }

  @Test func optionalFieldsMayBeMissing() throws {
    let json = #"{"id": 1, "workflow_id": 2, "created_at": "2023-11-14T22:13:20Z"}"#
    let run = try JSONDecoder.github.decode(WorkflowRun.self, from: Data(json.utf8))
    #expect(run.headBranch == nil)
    #expect(run.actor == nil)
    #expect(run.headRepository == nil)
    #expect(run.runStartedAt == nil)
    #expect(run.state == .neutral)
  }

  @Test func decodesFractionalSecondTimestamps() throws {
    let json = """
      {"total_count": 2, "workflow_runs": [
        {"id": 1, "workflow_id": 2, "created_at": "2023-11-14T22:13:20.123Z",
         "run_started_at": "2023-11-14T22:13:21.5Z", "updated_at": "2023-11-14T22:14:20.999Z"},
        {"id": 2, "workflow_id": 2, "created_at": "2023-11-14T22:13:20Z"}
      ]}
      """
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Data(json.utf8))
    #expect(page.runs.map(\.id) == [1, 2])
    let fractional = page.runs[0]
    #expect(abs(fractional.createdAt.timeIntervalSince1970 - 1_700_000_000.123) < 0.001)
    #expect(abs((fractional.runStartedAt?.timeIntervalSince1970 ?? 0) - 1_700_000_001.5) < 0.001)
    #expect(page.runs[1].createdAt == Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test func oneBadRunDoesNotDropThePage() throws {
    let json = """
      {"total_count": 3, "workflow_runs": [
        {"id": 1, "workflow_id": 2, "created_at": "2023-11-14T22:13:20Z"},
        {"id": "not a number"},
        {"id": 3, "workflow_id": 2, "created_at": "2023-11-14T22:13:20Z"}
      ]}
      """
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Data(json.utf8))
    #expect(page.runs.map(\.id) == [1, 3])
  }

  @Test(
    arguments: [
      ("in_progress", nil, RunState.running),
      ("queued", nil, .queued),
      ("waiting", nil, .queued),
      ("requested", nil, .queued),
      ("pending", nil, .queued),
      ("completed", "success", .passed),
      ("completed", "failure", .failed),
      ("completed", "timed_out", .failed),
      ("completed", "startup_failure", .failed),
      ("completed", "action_required", .queued),
      ("completed", "cancelled", .neutral),
      ("completed", "skipped", .neutral),
      ("completed", "neutral", .neutral),
      ("completed", "stale", .neutral),
      ("completed", nil, .neutral),
      ("mystery", nil, .neutral),
    ] as [(String, String?, RunState)])
  func mapsStatusAndConclusionToState(status: String, conclusion: String?, expected: RunState) {
    #expect(RunState(status: status, conclusion: conclusion) == expected)
  }

  @Test func runningWinsOverAStaleConclusion() {
    #expect(RunState(status: "in_progress", conclusion: "failure") == .running)
  }

  @Test func mostUrgentStateWinsOverall() {
    #expect(RunState.mostUrgent([.passed, .neutral, .running]) == .running)
    #expect(RunState.mostUrgent([.passed, .queued, .failed, .running]) == .failed)
    #expect(RunState.mostUrgent([.neutral, .passed]) == .passed)
    #expect(RunState.mostUrgent([]) == .neutral)
  }
}
