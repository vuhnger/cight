import Foundation
import Testing

@testable import CightCore

struct RunGroupingTests {
  @Test func keepsOnlyTheNewestRunPerWorkflowBranchAndHeadRepository() {
    let runs = [
      makeRun(id: 1, workflow: 1, branch: "main", created: 0),
      makeRun(id: 2, workflow: 1, branch: "main", created: 10),
      makeRun(id: 3, workflow: 2, branch: "main", created: 5),
      makeRun(id: 4, workflow: 1, branch: "feature", created: 1),
    ]
    let latest = RunGrouping.latestRuns(runs)
    #expect(Set(latest.map(\.id)) == [2, 3, 4])
  }

  @Test func forkRunsWithTheSameBranchNameDoNotCollide() {
    let runs = [
      makeRun(id: 1, branch: "fix", created: 0, headRepo: 1),
      makeRun(id: 2, branch: "fix", created: 10, headRepo: 2),
    ]
    #expect(Set(RunGrouping.latestRuns(runs).map(\.id)) == [1, 2])
  }

  @Test func myBranchesIncludeActorTriggeringActorAndTheDefaultBranch() {
    let runs = [
      makeRun(id: 1, branch: "main", actor: "other"),
      makeRun(id: 2, branch: "mine", actor: "me"),
      makeRun(id: 3, branch: "rerun", actor: "other", triggering: "me"),
      makeRun(id: 4, branch: "theirs", actor: "other"),
      makeRun(id: 5, branch: "mine", actor: "other"),
    ]
    let kept = RunGrouping.mine(runs, repoId: 1, defaultBranch: "main", viewer: "me")
    #expect(Set(kept.map(\.id)) == [1, 2, 3, 5])
  }

  @Test func aForkBranchNamedLikeTheDefaultBranchIsNotTheDefaultBranch() {
    let runs = [
      makeRun(id: 1, branch: "main", headRepo: 1),
      makeRun(id: 2, branch: "main", conclusion: "failure", actor: "stranger", headRepo: 2),
    ]
    let kept = RunGrouping.mine(runs, repoId: 1, defaultBranch: "main", viewer: "me")
    #expect(kept.map(\.id) == [1])
  }

  @Test func myForkBranchesAreMineButOtherForksWithTheSameBranchNameAreNot() {
    let runs = [
      makeRun(id: 1, branch: "fix", actor: "me", headRepo: 2),
      makeRun(id: 2, branch: "fix", actor: "stranger", headRepo: 3),
    ]
    let kept = RunGrouping.mine(runs, repoId: 1, defaultBranch: "main", viewer: "me")
    #expect(kept.map(\.id) == [1])
  }

  @Test func aFailingForkMainDoesNotTurnTheRepoRed() {
    let repo = RepoRuns(
      id: 1, fullName: "o/r", defaultBranch: "main",
      runs: [
        makeRun(id: 1, branch: "main", created: 10, headRepo: 1),
        makeRun(id: 2, branch: "main", conclusion: "failure", created: 20, actor: "x", headRepo: 2),
      ])
    let own = RunGrouping.groups([repo], viewer: "me")
    #expect(own.first?.state == .passed)
    #expect(own.first?.branches.map(\.branch) == ["main"])
  }

  @Test func ordersReposByUrgencyThenRecency() {
    let passedRepo = RepoRuns(
      id: 1, fullName: "o/passed", defaultBranch: "main",
      runs: [makeRun(id: 1, created: 500)])
    let failedRepo = RepoRuns(
      id: 1, fullName: "o/failed", defaultBranch: "main",
      runs: [
        makeRun(id: 2, workflow: 1, branch: "pass", created: 900),
        makeRun(id: 3, workflow: 1, branch: "old-fail", conclusion: "failure", created: 100),
        makeRun(id: 4, workflow: 1, branch: "new-fail", conclusion: "failure", created: 300),
        makeRun(id: 5, workflow: 2, branch: "old-fail", created: 50),
      ])
    let runningRepo = RepoRuns(
      id: 1, fullName: "o/running", defaultBranch: "main",
      runs: [makeRun(id: 6, status: "in_progress", conclusion: nil, created: 50)])

    let groups = RunGrouping.groups(
      [passedRepo, runningRepo, failedRepo], viewer: "me")

    #expect(groups.map(\.fullName) == ["o/failed", "o/running", "o/passed"])
    #expect(groups.map(\.state) == [.failed, .running, .passed])
    let branches = groups[0].branches
    #expect(branches.map(\.branch) == ["pass", "new-fail", "old-fail"])
    #expect(branches.map(\.state) == [.passed, .failed, .failed])
    #expect(branches[2].runs.map(\.id) == [3, 5])
  }

  @Test func aNewerPassedBranchComesBeforeAnOlderFailedBranch() {
    let repo = RepoRuns(
      id: 1, fullName: "o/r", defaultBranch: "main",
      runs: [
        makeRun(id: 1, branch: "old", conclusion: "failure", created: 100),
        makeRun(id: 2, branch: "new", created: 200),
      ])
    let group = RunGrouping.groups([repo], viewer: "me")[0]
    #expect(group.branches.map(\.branch) == ["new", "old"])
    #expect(group.state == .failed)
  }

  @Test func aNewerPassedRunComesBeforeAnOlderFailedRunInOneBranch() {
    let repo = RepoRuns(
      id: 1, fullName: "o/r", defaultBranch: "main",
      runs: [
        makeRun(id: 1, workflow: 1, conclusion: "failure", created: 100),
        makeRun(id: 2, workflow: 2, created: 200),
      ])
    let branch = RunGrouping.groups([repo], viewer: "me")[0].branches[0]
    #expect(branch.runs.map(\.id) == [2, 1])
    #expect(branch.state == .failed)
  }

  @Test func recencyBreaksTiesBetweenRepos() {
    let older = RepoRuns(
      id: 1, fullName: "o/older", defaultBranch: "main", runs: [makeRun(id: 1, created: 0)])
    let newer = RepoRuns(
      id: 1, fullName: "o/newer", defaultBranch: "main", runs: [makeRun(id: 2, created: 60)])
    let groups = RunGrouping.groups([older, newer], viewer: "me")
    #expect(groups.map(\.fullName) == ["o/newer", "o/older"])
  }

  @Test func appliesTheFilterBeforeGrouping() {
    let repo = RepoRuns(
      id: 1, fullName: "o/r", defaultBranch: "main",
      runs: [
        makeRun(id: 1, branch: "main"),
        makeRun(id: 2, branch: "other", conclusion: "failure", actor: "x"),
      ])
    let groups = RunGrouping.groups([repo], viewer: "me")
    #expect(groups.first?.branches.map(\.branch) == ["main"])
    #expect(groups.first?.state == .passed)
  }
}
