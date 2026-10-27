import Foundation
import Testing

@testable import CightCore

private func passed(_ id: Int, branch: String = "main", attempt: Int = 1) -> WorkflowRun {
  makeRun(id: id, branch: branch, created: TimeInterval(id), attempt: attempt)
}

private func failed(_ id: Int, branch: String = "main", attempt: Int = 1) -> WorkflowRun {
  makeRun(
    id: id, branch: branch, conclusion: "failure", created: TimeInterval(id), attempt: attempt)
}

private func running(_ id: Int, branch: String = "main", attempt: Int = 1) -> WorkflowRun {
  makeRun(
    id: id, branch: branch, status: "in_progress", conclusion: nil, created: TimeInterval(id),
    attempt: attempt)
}

private func queued(_ id: Int) -> WorkflowRun {
  makeRun(id: id, status: "queued", conclusion: nil, created: TimeInterval(id))
}

private func kinds(_ events: [RunEvent]) -> [RunEvent.Kind] {
  events.map(\.kind)
}

struct RunTrackerTests {
  @Test func firstPollPerRepoIsASilentBaseline() {
    var tracker = RunTracker()
    #expect(
      tracker.ingest(repo: "o/a", runs: [running(1), failed(2, branch: "x")], filter: .all).isEmpty)
    #expect(tracker.ingest(repo: "o/b", runs: [running(3)], filter: .all).isEmpty)
  }

  @Test func reportsAStartWhenANewRunIsRunning() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .all)
    let events = tracker.ingest(repo: "o/a", runs: [running(2)], filter: .all)
    #expect(kinds(events) == [.started])
    #expect(events.first?.run.id == 2)
    #expect(events.first?.repo == "o/a")
  }

  @Test func reportsAStartWhenAQueuedRunBeginsRunning() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [queued(2)], filter: .all)
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [running(2)], filter: .all)) == [.started])
  }

  @Test func doesNotReportAQueuedRunAsStarted() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .all)
    #expect(tracker.ingest(repo: "o/a", runs: [queued(2)], filter: .all).isEmpty)
  }

  @Test func reportsAFailureWhenARunningRunFails() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [running(2)], filter: .all)
    let events = tracker.ingest(repo: "o/a", runs: [failed(2)], filter: .all)
    #expect(kinds(events) == [.failed])
  }

  @Test func reportsAFailureForARunThatFailedBetweenPolls() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .all)
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [failed(2)], filter: .all)) == [.failed])
  }

  @Test func reportsRecoveryWhenABranchPassesAfterAFailure() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [failed(1)], filter: .all)
    let events = tracker.ingest(repo: "o/a", runs: [passed(2)], filter: .all)
    #expect(kinds(events) == [.recovered])
  }

  @Test func aReRunOfAFailedRunThatPassesCountsAsRecovered() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [failed(5)], filter: .all)
    #expect(
      kinds(tracker.ingest(repo: "o/a", runs: [running(5, attempt: 2)], filter: .all)) == [.started]
    )
    #expect(
      kinds(tracker.ingest(repo: "o/a", runs: [passed(5, attempt: 2)], filter: .all)) == [
        .recovered
      ])
  }

  @Test func aPassAfterAPassIsNotARecovery() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .all)
    #expect(tracker.ingest(repo: "o/a", runs: [passed(2)], filter: .all).isEmpty)
  }

  @Test func aFailureOnOneBranchDoesNotMakeAPassOnAnotherBranchARecovery() {
    var tracker = RunTracker()
    _ = tracker.ingest(
      repo: "o/a", runs: [failed(1, branch: "x"), passed(2, branch: "y")], filter: .all)
    let events = tracker.ingest(
      repo: "o/a", runs: [failed(1, branch: "x"), passed(3, branch: "y")], filter: .all)
    #expect(events.isEmpty)
  }

  @Test func usesOnlyTheNewestRunPerKeyOnARawNewestFirstPage() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .all)
    let page = [running(3), failed(2), passed(1)]
    let events = tracker.ingest(repo: "o/a", runs: page, filter: .all)
    #expect(kinds(events) == [.started])
    #expect(events.first?.run.id == 3)
    #expect(tracker.ingest(repo: "o/a", runs: page, filter: .all).isEmpty)
    let finished = [failed(3), failed(2), passed(1)]
    #expect(kinds(tracker.ingest(repo: "o/a", runs: finished, filter: .all)) == [.failed])
  }

  @Test func neverFiresTheSameEventTwice() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .all)
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [running(2)], filter: .all)) == [.started])
    #expect(tracker.ingest(repo: "o/a", runs: [running(2)], filter: .all).isEmpty)
    #expect(tracker.ingest(repo: "o/a", runs: [queued(2)], filter: .all).isEmpty)
    #expect(tracker.ingest(repo: "o/a", runs: [running(2)], filter: .all).isEmpty)
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [failed(2)], filter: .all)) == [.failed])
    #expect(tracker.ingest(repo: "o/a", runs: [failed(2)], filter: .all).isEmpty)
  }

  @Test func aChangeOfFilterRebaselinesEveryRepoSilently() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)], filter: .defaultBranch)
    _ = tracker.ingest(repo: "o/b", runs: [passed(2)], filter: .defaultBranch)

    #expect(tracker.ingest(repo: "o/a", runs: [failed(3, branch: "x")], filter: .all).isEmpty)
    #expect(tracker.ingest(repo: "o/b", runs: [failed(4, branch: "y")], filter: .all).isEmpty)

    #expect(
      kinds(
        tracker.ingest(
          repo: "o/a", runs: [failed(3, branch: "x"), failed(5, branch: "z")], filter: .all))
        == [.failed])
  }
}
