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

  @Test func filtersToTheDefaultBranch() {
    let runs = [
      makeRun(id: 1, branch: "main"),
      makeRun(id: 2, branch: "feature", actor: "me"),
    ]
    let kept = RunGrouping.filter(
      runs, repoId: 1, defaultBranch: "main", viewer: "me", mode: .defaultBranch)
    #expect(kept.map(\.id) == [1])
  }

  @Test func myBranchesIncludeActorTriggeringActorAndTheDefaultBranch() {
    let runs = [
      makeRun(id: 1, branch: "main", actor: "other"),
      makeRun(id: 2, branch: "mine", actor: "me"),
      makeRun(id: 3, branch: "rerun", actor: "other", triggering: "me"),
      makeRun(id: 4, branch: "theirs", actor: "other"),
      makeRun(id: 5, branch: "mine", actor: "other"),
    ]
    let kept = RunGrouping.filter(runs, repoId: 1, defaultBranch: "main", viewer: "me", mode: .mine)
    #expect(Set(kept.map(\.id)) == [1, 2, 3, 5])
  }

  @Test func aForkBranchNamedLikeTheDefaultBranchIsNotTheDefaultBranch() {
    let runs = [
      makeRun(id: 1, branch: "main", headRepo: 1),
      makeRun(id: 2, branch: "main", conclusion: "failure", actor: "stranger", headRepo: 2),
    ]
    for mode in [BranchFilter.defaultBranch, .mine] {
      let kept = RunGrouping.filter(
        runs, repoId: 1, defaultBranch: "main", viewer: "me", mode: mode)
      #expect(kept.map(\.id) == [1])
    }
  }

  @Test func myForkBranchesAreMineButOtherForksWithTheSameBranchNameAreNot() {
    let runs = [
      makeRun(id: 1, branch: "fix", actor: "me", headRepo: 2),
      makeRun(id: 2, branch: "fix", actor: "stranger", headRepo: 3),
    ]
    let kept = RunGrouping.filter(
      runs, repoId: 1, defaultBranch: "main", viewer: "me", mode: .mine)
    #expect(kept.map(\.id) == [1])
  }

  @Test func aFailingForkMainDoesNotTurnTheRepoRedUnderTheDefaultBranchFilter() {
    let repo = RepoRuns(
      id: 1, fullName: "o/r", defaultBranch: "main",
      runs: [
        makeRun(id: 1, branch: "main", created: 10, headRepo: 1),
        makeRun(id: 2, branch: "main", conclusion: "failure", created: 20, actor: "x", headRepo: 2),
      ])
    let own = RunGrouping.groups([repo], viewer: "me", filter: .defaultBranch)
    #expect(own.first?.state == .passed)
    let all = RunGrouping.groups([repo], viewer: "me", filter: .all)
    #expect(all.first?.branches.map(\.branch) == ["owner2:main", "main"])
    #expect(all.first?.branches.map(\.state) == [.failed, .passed])
  }

  @Test func allKeepsEveryBranch() {
    let runs = [makeRun(id: 1, branch: "main"), makeRun(id: 2, branch: "x", actor: "other")]
    let kept = RunGrouping.filter(runs, repoId: 1, defaultBranch: "main", viewer: "me", mode: .all)
    #expect(kept.count == 2)
  }

  @Test func ordersReposBranchesAndRunsByUrgencyThenRecency() {
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
      [passedRepo, runningRepo, failedRepo], viewer: "me", filter: .all)

    #expect(groups.map(\.fullName) == ["o/failed", "o/running", "o/passed"])
    #expect(groups.map(\.state) == [.failed, .running, .passed])
    let branches = groups[0].branches
    #expect(branches.map(\.branch) == ["new-fail", "old-fail", "pass"])
    #expect(branches.map(\.state) == [.failed, .failed, .passed])
    #expect(branches[1].runs.map(\.id) == [3, 5])
  }

  @Test func recencyBreaksTiesBetweenRepos() {
    let older = RepoRuns(
      id: 1, fullName: "o/older", defaultBranch: "main", runs: [makeRun(id: 1, created: 0)])
    let newer = RepoRuns(
      id: 1, fullName: "o/newer", defaultBranch: "main", runs: [makeRun(id: 2, created: 60)])
    let groups = RunGrouping.groups([older, newer], viewer: "me", filter: .all)
    #expect(groups.map(\.fullName) == ["o/newer", "o/older"])
  }

  @Test func appliesTheFilterBeforeGrouping() {
    let repo = RepoRuns(
      id: 1, fullName: "o/r", defaultBranch: "main",
      runs: [
        makeRun(id: 1, branch: "main"),
        makeRun(id: 2, branch: "other", conclusion: "failure", actor: "x"),
      ])
    let groups = RunGrouping.groups([repo], viewer: "me", filter: .mine)
    #expect(groups.first?.branches.map(\.branch) == ["main"])
    #expect(groups.first?.state == .passed)
  }
}
