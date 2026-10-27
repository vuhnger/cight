import Foundation

public enum BranchFilter: Sendable, Equatable {
  case defaultBranch
  case mine
  case all
}

public struct RepoRuns: Sendable {
  public let id: Int
  public let fullName: String
  public let defaultBranch: String
  public let runs: [WorkflowRun]

  public init(id: Int, fullName: String, defaultBranch: String, runs: [WorkflowRun]) {
    self.id = id
    self.fullName = fullName
    self.defaultBranch = defaultBranch
    self.runs = runs
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

  public static func filter(
    _ runs: [WorkflowRun], repoId: Int, defaultBranch: String, viewer: String, mode: BranchFilter
  ) -> [WorkflowRun] {
    func isDefaultBranchOfRepo(_ run: WorkflowRun) -> Bool {
      run.branch == defaultBranch && run.headRepository?.id == repoId
    }
    switch mode {
    case .all:
      return runs
    case .defaultBranch:
      return runs.filter(isDefaultBranchOfRepo)
    case .mine:
      let mine = Set(
        runs.filter { $0.actor?.login == viewer || $0.triggeringActor?.login == viewer }
          .map(BranchKey.init))
      return runs.filter { isDefaultBranchOfRepo($0) || mine.contains(BranchKey($0)) }
    }
  }

  public static func groups(
    _ repos: [RepoRuns], viewer: String, filter mode: BranchFilter
  ) -> [RepoGroup] {
    repos
      .compactMap { repo -> RepoGroup? in
        let kept = filter(
          repo.runs, repoId: repo.id, defaultBranch: repo.defaultBranch, viewer: viewer, mode: mode)
        let latest = latestRuns(kept)
        guard !latest.isEmpty else { return nil }
        let branches = Dictionary(grouping: latest, by: BranchKey.init)
          .map { key, runs in
            BranchGroup(
              branch: displayName(key, repoId: repo.id, run: runs[0]),
              state: .mostUrgent(runs.map(\.state)), runs: sorted(runs))
          }
          .sorted {
            ($0.state.urgency, $1.recency, $0.branch) < ($1.state.urgency, $0.recency, $1.branch)
          }
        return RepoGroup(
          fullName: repo.fullName, state: .mostUrgent(branches.map(\.state)), branches: branches)
      }
      .sorted {
        ($0.state.urgency, $1.recency, $0.fullName) < ($1.state.urgency, $0.recency, $1.fullName)
      }
  }

  private static func displayName(_ key: BranchKey, repoId: Int, run: WorkflowRun) -> String {
    guard key.repositoryId != repoId,
      let owner = run.headRepository?.fullName?.split(separator: "/").first
    else { return key.branch }
    return "\(owner):\(key.branch)"
  }

  private static func sorted(_ runs: [WorkflowRun]) -> [WorkflowRun] {
    runs.sorted {
      ($0.state.urgency, $1.activityDate, $0.id) < ($1.state.urgency, $0.activityDate, $1.id)
    }
  }
}
