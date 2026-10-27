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
      tracker.ingest(repo: "o/a", runs: [running(1), failed(2, branch: "x")]).isEmpty)
    #expect(tracker.ingest(repo: "o/b", runs: [running(3)]).isEmpty)
  }

  @Test func reportsAStartWhenANewRunIsRunning() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    let events = tracker.ingest(repo: "o/a", runs: [running(2)])
    #expect(kinds(events) == [.started])
    #expect(events.first?.run.id == 2)
    #expect(events.first?.repo == "o/a")
  }

  @Test func reportsAStartWhenAQueuedRunBeginsRunning() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [queued(2)])
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [running(2)])) == [.started])
  }

  @Test func doesNotReportAQueuedRunAsStarted() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    #expect(tracker.ingest(repo: "o/a", runs: [queued(2)]).isEmpty)
  }

  @Test func reportsAFailureWhenARunningRunFails() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [running(2)])
    let events = tracker.ingest(repo: "o/a", runs: [failed(2)])
    #expect(kinds(events) == [.failed])
  }

  @Test func reportsAFailureForARunThatFailedBetweenPolls() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [failed(2)])) == [.failed])
  }

  @Test func reportsRecoveryWhenABranchPassesAfterAFailure() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [failed(1)])
    let events = tracker.ingest(repo: "o/a", runs: [passed(2)])
    #expect(kinds(events) == [.recovered])
  }

  @Test func aReRunOfAFailedRunThatPassesCountsAsRecovered() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [failed(5)])
    #expect(
      kinds(tracker.ingest(repo: "o/a", runs: [running(5, attempt: 2)])) == [.started]
    )
    #expect(
      kinds(tracker.ingest(repo: "o/a", runs: [passed(5, attempt: 2)])) == [
        .recovered
      ])
  }

  @Test func aPassAfterAPassIsNotARecovery() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    #expect(tracker.ingest(repo: "o/a", runs: [passed(2)]).isEmpty)
  }

  @Test func aFailureOnOneBranchDoesNotMakeAPassOnAnotherBranchARecovery() {
    var tracker = RunTracker()
    _ = tracker.ingest(
      repo: "o/a", runs: [failed(1, branch: "x"), passed(2, branch: "y")])
    let events = tracker.ingest(
      repo: "o/a", runs: [failed(1, branch: "x"), passed(3, branch: "y")])
    #expect(events.isEmpty)
  }

  @Test func usesOnlyTheNewestRunPerKeyOnARawNewestFirstPage() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    let page = [running(3), failed(2), passed(1)]
    let events = tracker.ingest(repo: "o/a", runs: page)
    #expect(kinds(events) == [.started])
    #expect(events.first?.run.id == 3)
    #expect(tracker.ingest(repo: "o/a", runs: page).isEmpty)
    let finished = [failed(3), failed(2), passed(1)]
    #expect(kinds(tracker.ingest(repo: "o/a", runs: finished)) == [.failed])
  }

  @Test func neverFiresTheSameEventTwice() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [running(2)])) == [.started])
    #expect(tracker.ingest(repo: "o/a", runs: [running(2)]).isEmpty)
    #expect(tracker.ingest(repo: "o/a", runs: [queued(2)]).isEmpty)
    #expect(tracker.ingest(repo: "o/a", runs: [running(2)]).isEmpty)
    #expect(kinds(tracker.ingest(repo: "o/a", runs: [failed(2)])) == [.failed])
    #expect(tracker.ingest(repo: "o/a", runs: [failed(2)]).isEmpty)
  }

  @Test func keepsTheFiredSetBoundedToRunsStillOnThePage() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(0)])
    for id in 1...100 {
      _ = tracker.ingest(repo: "o/a", runs: [running(id)])
      _ = tracker.ingest(repo: "o/a", runs: [failed(id)])
    }
    #expect(tracker.firedCount <= 2)
  }

  @Test func pruningOneRepoLeavesTheOthersDeduplicated() {
    var tracker = RunTracker()
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    _ = tracker.ingest(repo: "o/b", runs: [passed(2)])
    #expect(kinds(tracker.ingest(repo: "o/b", runs: [running(3)])) == [.started])
    _ = tracker.ingest(repo: "o/a", runs: [passed(1)])
    #expect(tracker.ingest(repo: "o/b", runs: [queued(3)]).isEmpty)
    #expect(tracker.ingest(repo: "o/b", runs: [running(3)]).isEmpty)
  }
}
