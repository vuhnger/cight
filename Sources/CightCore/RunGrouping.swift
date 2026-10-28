import Foundation

public struct RepoRuns: Sendable {
  public let id: Int
  public let fullName: String
  public let defaultBranch: String
  public let runs: [WorkflowRun]
  public let liveBranches: Set<String>?

  public init(
    id: Int, fullName: String, defaultBranch: String, runs: [WorkflowRun],
    liveBranches: Set<String>? = nil
  ) {
    self.id = id
    self.fullName = fullName
    self.defaultBranch = defaultBranch
    self.runs = runs
    self.liveBranches = liveBranches
  }
}

public struct BranchGroup: Sendable, Equatable {
  public let branch: String
  public let state: RunState
  public let runs: [WorkflowRun]

  var recency: Date {
    runs.map(\.activityDate).max() ?? .distantPast
  }
}

public struct RepoGroup: Sendable, Equatable {
  public let fullName: String
  public let state: RunState
  public let branches: [BranchGroup]

  var recency: Date {
    branches.map(\.recency).max() ?? .distantPast
  }
}

public enum RunGrouping {
  private struct BranchKey: Hashable {
    let branch: String
    let repositoryId: Int?

    init(_ run: WorkflowRun) {
      branch = run.branch
      repositoryId = run.headRepository?.id
    }
  }

  private struct RunKey: Hashable {
    let workflowId: Int
    let branch: String?
    let headRepositoryId: Int?
  }

  public static func latestRuns(_ runs: [WorkflowRun]) -> [WorkflowRun] {
    var newest: [RunKey: WorkflowRun] = [:]
    for run in runs {
      let key = RunKey(
        workflowId: run.workflowId, branch: run.headBranch, headRepositoryId: run.headRepository?.id
      )
      if let current = newest[key], (current.createdAt, current.id) >= (run.createdAt, run.id) {
        continue
      }
      newest[key] = run
    }
    return newest.values.sorted { $0.id < $1.id }
  }

  public static func mine(
    _ runs: [WorkflowRun], repoId: Int, defaultBranch: String, viewer: String
  ) -> [WorkflowRun] {
    let mine = Set(
      runs.filter { $0.actor?.login == viewer || $0.triggeringActor?.login == viewer }
        .map(BranchKey.init))
    return runs.filter {
      ($0.branch == defaultBranch && $0.headRepository?.id == repoId)
        || mine.contains(BranchKey($0))
    }
  }

  public static func groups(
    _ repos: [RepoRuns], viewer: String
  ) -> [RepoGroup] {
    repos
      .compactMap { repo -> RepoGroup? in
        let kept = mine(
          repo.runs, repoId: repo.id, defaultBranch: repo.defaultBranch, viewer: viewer)
        let latest = latestRuns(kept).filter {
          $0.conclusion != "skipped" && isLive($0, in: repo)
        }
        guard !latest.isEmpty else { return nil }
        let branches = Dictionary(grouping: latest, by: BranchKey.init)
          .map { key, runs in
            BranchGroup(
              branch: displayName(key, repoId: repo.id, run: runs[0]),
              state: .mostUrgent(runs.map(\.state)), runs: sorted(runs))
          }
          .sorted { ($1.recency, $0.branch) < ($0.recency, $1.branch) }
        return RepoGroup(
          fullName: repo.fullName, state: .mostUrgent(branches.map(\.state)), branches: branches)
      }
      .sorted {
        ($0.state.urgency, $1.recency, $0.fullName) < ($1.state.urgency, $0.recency, $1.fullName)
      }
  }

  private static func isLive(_ run: WorkflowRun, in repo: RepoRuns) -> Bool {
    guard let live = repo.liveBranches else { return true }
    return run.branch == repo.defaultBranch || run.headRepository?.id != repo.id
      || live.contains(run.branch)
  }

  private static func displayName(_ key: BranchKey, repoId: Int, run: WorkflowRun) -> String {
    guard key.repositoryId != repoId,
      let owner = run.headRepository?.fullName?.split(separator: "/").first
    else { return key.branch }
    return "\(owner):\(key.branch)"
  }

  private static func sorted(_ runs: [WorkflowRun]) -> [WorkflowRun] {
    runs.sorted { ($1.activityDate, $0.id) < ($0.activityDate, $1.id) }
  }
}
