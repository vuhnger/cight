import Foundation
import Testing

@testable import CightCore

private func groups(
  _ runs: [WorkflowRun], live: Set<String>?
) -> [RepoGroup] {
  let repo = RepoRuns(
    id: 1, fullName: "o/r", defaultBranch: "main", runs: runs, liveBranches: live)
  return RunGrouping.groups([repo], viewer: "me")
}

struct RunVisibilityTests {
  @Test func skippedRunsAreHidden() {
    let result = groups(
      [
        makeRun(id: 1, workflow: 1, branch: "main", created: 0),
        makeRun(id: 2, workflow: 2, branch: "main", conclusion: "skipped", created: 5),
      ], live: nil)
    #expect(result.first?.branches.first?.runs.map(\.id) == [1])
  }

  @Test func aBranchWithOnlySkippedRunsDisappears() {
    let result = groups(
      [
        makeRun(id: 1, branch: "main"),
        makeRun(id: 2, workflow: 2, branch: "bot", conclusion: "skipped"),
      ], live: nil)
    #expect(result.first?.branches.map(\.branch) == ["main"])
  }

  @Test func aSkippedNewestRunDoesNotResurrectAnOlderRunOfTheSameWorkflow() {
    let result = groups(
      [
        makeRun(id: 1, workflow: 1, branch: "main", conclusion: "failure", created: 0),
        makeRun(id: 2, workflow: 1, branch: "main", conclusion: "skipped", created: 10),
      ], live: nil)
    #expect(result.isEmpty)
  }

  @Test func branchesThatNoLongerExistAreDropped() {
    let result = groups(
      [
        makeRun(id: 1, branch: "main"),
        makeRun(id: 2, branch: "feat/merged"),
        makeRun(id: 3, branch: "feat/open"),
      ], live: ["main", "feat/open"])
    #expect(Set(result.first?.branches.map(\.branch) ?? []) == ["main", "feat/open"])
  }

  @Test func theDefaultBranchSurvivesEvenWhenTheListOmitsIt() {
    let result = groups([makeRun(id: 1, branch: "main")], live: ["other"])
    #expect(result.first?.branches.map(\.branch) == ["main"])
  }

  @Test func forkRunsSurviveBecauseTheirBranchLivesInTheFork() {
    let result = groups(
      [makeRun(id: 1, branch: "fix", headRepo: 2), makeRun(id: 2, workflow: 2, branch: "gone")],
      live: ["main"])
    #expect(result.first?.branches.map(\.branch) == ["owner2:fix"])
  }

  @Test func anUnknownBranchListKeepsEverything() {
    let result = groups([makeRun(id: 1, branch: "feat/x")], live: nil)
    #expect(result.first?.branches.map(\.branch) == ["feat/x"])
  }

  @Test func otherPeoplesBranchesStayHiddenEvenWhenTheyAreLive() {
    let result = groups(
      [makeRun(id: 1, branch: "main"), makeRun(id: 2, branch: "feat/x", actor: "stranger")],
      live: ["main", "feat/x"])
    #expect(result.first?.branches.map(\.branch) == ["main"])
  }
}
