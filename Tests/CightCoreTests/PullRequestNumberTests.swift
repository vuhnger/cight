import Foundation
import Testing

@testable import CightCore

struct PullRequestNumberTests {
  @Test func decodesTheFirstPullRequestOfARecordedRun() throws {
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Fixture.data("pr-runs"))
    #expect(page.runs.count == 2)
    #expect(page.runs[0].pullRequestNumber == 7)
  }

  @Test func aRunWithAnEmptyPullRequestListHasNoNumber() throws {
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Fixture.data("pr-runs"))
    #expect(page.runs[1].pullRequestNumber == nil)
  }

  @Test func aRunWithoutThePullRequestKeyHasNoNumber() throws {
    let page = try JSONDecoder.github.decode(RunsPage.self, from: Fixture.data("runs"))
    #expect(page.runs.allSatisfy { $0.pullRequestNumber == nil })
  }

  @Test func theFirstOfSeveralPullRequestsWins() throws {
    let json = """
      {"id": 1, "workflow_id": 2, "created_at": "2026-10-27T20:59:22Z",
       "pull_requests": [{"number": 9}, {"number": 3}]}
      """
    let run = try JSONDecoder.github.decode(WorkflowRun.self, from: Data(json.utf8))
    #expect(run.pullRequestNumber == 9)
  }
}
