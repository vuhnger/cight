import Foundation

public struct RunEvent: Sendable, Equatable {
  public enum Kind: Sendable, Hashable {
    case started
    case failed
    case recovered
  }

  public let kind: Kind
  public let repo: String
  public let run: WorkflowRun
  public var host = Repo.githubHost
}

public struct RunTracker: Sendable {
  private struct Key: Hashable {
    let repo: String
    let workflowId: Int
    let branch: String?
    let headRepositoryId: Int?
  }

  private struct Seen {
    let runId: Int
    let attempt: Int?
    let state: RunState

    func matches(_ run: WorkflowRun) -> Bool {
      runId == run.id && attempt == run.runAttempt && state == run.state
    }
  }

  private struct Fired: Hashable {
    let repo: String
    let kind: RunEvent.Kind
    let runId: Int
    let attempt: Int?
  }

  private var baselinedRepos: Set<String> = []
  private var seen: [Key: Seen] = [:]
  private var lastSettled: [Key: RunState] = [:]
  private var fired: Set<Fired> = []

  var firedCount: Int { fired.count }

  public init() {}

  public mutating func ingest(
    repo: String, runs: [WorkflowRun], host: String = Repo.githubHost
  ) -> [RunEvent] {
    let isBaseline = baselinedRepos.insert(repo).inserted
    let latest = RunGrouping.latestRuns(runs)
    let present = Set(latest.map(\.id))
    fired = fired.filter { $0.repo != repo || present.contains($0.runId) }
    var events: [RunEvent] = []
    for run in latest {
      let key = Key(
        repo: repo, workflowId: run.workflowId, branch: run.headBranch,
        headRepositoryId: run.headRepository?.id)
      let unchanged = seen[key]?.matches(run) ?? false
      let settledBefore = lastSettled[key]
      seen[key] = Seen(runId: run.id, attempt: run.runAttempt, state: run.state)
      if run.state == .passed || run.state == .failed {
        lastSettled[key] = run.state
      }
      guard !isBaseline, !unchanged, let kind = kind(of: run, settledBefore: settledBefore) else {
        continue
      }
      if fired.insert(Fired(repo: repo, kind: kind, runId: run.id, attempt: run.runAttempt))
        .inserted
      {
        events.append(RunEvent(kind: kind, repo: repo, run: run, host: host))
      }
    }
    return events
  }

  private func kind(of run: WorkflowRun, settledBefore: RunState?) -> RunEvent.Kind? {
    switch run.state {
    case .running: .started
    case .failed: .failed
    case .passed: settledBefore == .failed ? .recovered : nil
    case .queued, .neutral: nil
    }
  }
}
