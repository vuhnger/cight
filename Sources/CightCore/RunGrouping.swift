import Foundation

public enum BranchFilter: Sendable, Equatable {
  case defaultBranch
  case mine
  case all
}

public struct RepoRuns: Sendable {
  public let fullName: String
  public let defaultBranch: String
  public let runs: [WorkflowRun]

  public init(fullName: String, defaultBranch: String, runs: [WorkflowRun]) {
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
    return Array(newest.values)
  }

  public static func filter(
    _ runs: [WorkflowRun], defaultBranch: String, viewer: String, mode: BranchFilter
  ) -> [WorkflowRun] {
    switch mode {
    case .all:
      return runs
    case .defaultBranch:
      return runs.filter { $0.branch == defaultBranch }
    case .mine:
      let mine = Set(
        runs.filter { $0.actor?.login == viewer || $0.triggeringActor?.login == viewer }.map(
          \.branch))
      return runs.filter { $0.branch == defaultBranch || mine.contains($0.branch) }
    }
  }

  public static func groups(
    _ repos: [RepoRuns], viewer: String, filter mode: BranchFilter
  ) -> [RepoGroup] {
    repos
      .compactMap { repo -> RepoGroup? in
        let kept = filter(repo.runs, defaultBranch: repo.defaultBranch, viewer: viewer, mode: mode)
        let latest = latestRuns(kept)
        guard !latest.isEmpty else { return nil }
        let branches = Dictionary(grouping: latest, by: \.branch)
          .map { branch, runs in
            BranchGroup(branch: branch, state: .mostUrgent(runs.map(\.state)), runs: sorted(runs))
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

  private static func sorted(_ runs: [WorkflowRun]) -> [WorkflowRun] {
    runs.sorted {
      ($0.state.urgency, $1.activityDate, $0.id) < ($1.state.urgency, $0.activityDate, $1.id)
    }
  }
}
