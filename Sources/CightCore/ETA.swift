import Foundation

public struct ETAEstimate: Sendable, Equatable {
  public let median: TimeInterval
  public let sampleCount: Int
}

public struct RunProgress: Sendable, Equatable {
  public let fraction: Double
  public let isOverdue: Bool
  public let overdueBy: TimeInterval
}

public enum ETA {
  private static let maxSamples = 10

  public static func estimate(for run: WorkflowRun, among runs: [WorkflowRun]) -> ETAEstimate? {
    let durations =
      runs
      .filter { $0.workflowId == run.workflowId && $0.event == run.event && $0.state == .passed }
      .sorted { $0.createdAt > $1.createdAt }
      .compactMap(duration)
      .prefix(maxSamples)
      .sorted()
    guard !durations.isEmpty else { return nil }
    let middle = durations.count / 2
    let median =
      durations.count.isMultiple(of: 2)
      ? (durations[middle - 1] + durations[middle]) / 2 : durations[middle]
    return ETAEstimate(median: median, sampleCount: durations.count)
  }

  public static func progress(elapsed: TimeInterval, median: TimeInterval) -> RunProgress {
    RunProgress(
      fraction: min(1, elapsed / median),
      isOverdue: elapsed > median,
      overdueBy: max(0, elapsed - median))
  }

  private static func duration(_ run: WorkflowRun) -> TimeInterval? {
    guard let started = run.runStartedAt, let finished = run.updatedAt else { return nil }
    let seconds = finished.timeIntervalSince(started)
    return seconds > 0 ? seconds : nil
  }
}
