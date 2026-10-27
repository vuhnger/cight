import Foundation
import Testing

@testable import CightCore

struct ETATests {
  private let running = makeRun(
    id: 999, workflow: 1, status: "in_progress", conclusion: nil, event: "push",
    created: 10_000, started: 10_000)

  @Test func usesTheMedianOfTheNewestTenSuccessfulRunsOfTheSameWorkflowAndEvent() {
    var runs = [
      successfulRun(id: 1, created: 0, duration: 1000),
      successfulRun(id: 2, created: 1, duration: 1000),
    ]
    for index in 1...10 {
      runs.append(
        successfulRun(
          id: 10 + index, created: TimeInterval(100 + index), duration: Double(index) * 10))
    }
    runs.append(successfulRun(id: 30, workflow: 2, created: 500, duration: 9000))
    runs.append(successfulRun(id: 31, event: "schedule", created: 500, duration: 9000))
    runs.append(
      makeRun(
        id: 32, conclusion: "failure", created: 500, started: 500, updated: 9500))

    let estimate = ETA.estimate(for: running, among: runs)

    #expect(estimate?.median == 55)
    #expect(estimate?.sampleCount == 10)
  }

  @Test func medianOfAnOddCountIsTheMiddleValue() {
    let runs = [
      successfulRun(id: 1, created: 0, duration: 60),
      successfulRun(id: 2, created: 1, duration: 600),
      successfulRun(id: 3, created: 2, duration: 120),
    ]
    let estimate = ETA.estimate(for: running, among: runs)
    #expect(estimate?.median == 120)
    #expect(estimate?.sampleCount == 3)
  }

  @Test func reportsTheSampleCountSoTheUICanMarkLowConfidence() {
    let runs = [
      successfulRun(id: 1, created: 0, duration: 60),
      successfulRun(id: 2, created: 1, duration: 100),
    ]
    let estimate = ETA.estimate(for: running, among: runs)
    #expect(estimate?.median == 80)
    #expect(estimate?.sampleCount == 2)
  }

  @Test func returnsNilWithoutSuccessfulRuns() {
    let runs = [makeRun(id: 1, conclusion: "failure", created: 0, started: 0, updated: 60)]
    #expect(ETA.estimate(for: running, among: runs) == nil)
    #expect(ETA.estimate(for: running, among: []) == nil)
  }

  @Test func skipsRunsWithoutUsableTimestamps() {
    let runs = [
      makeRun(id: 1, created: 0),
      makeRun(id: 2, created: 1, started: 100, updated: 40),
      successfulRun(id: 3, created: 2, duration: 90),
    ]
    let estimate = ETA.estimate(for: running, among: runs)
    #expect(estimate?.median == 90)
    #expect(estimate?.sampleCount == 1)
  }

  @Test func progressIsTheElapsedShareOfTheMedian() {
    let progress = ETA.progress(elapsed: 30, median: 120)
    #expect(progress.fraction == 0.25)
    #expect(!progress.isOverdue)
    #expect(progress.overdueBy == 0)
  }

  @Test func progressIsCappedAtOneAndFlagsOverdue() {
    let progress = ETA.progress(elapsed: 150, median: 120)
    #expect(progress.fraction == 1)
    #expect(progress.isOverdue)
    #expect(progress.overdueBy == 30)
  }

  @Test func reachingTheMedianExactlyIsNotOverdue() {
    let progress = ETA.progress(elapsed: 120, median: 120)
    #expect(progress.fraction == 1)
    #expect(!progress.isOverdue)
  }
}
