import Foundation

public enum MenuBarGlyph: Sendable, Equatable {
  case failed
  case running(progress: Double?)
  case overdue
  case queued
  case passed
  case signedOut
  case idle
}

public struct MenuBarRepo: Sendable {
  public let visible: [WorkflowRun]
  public let history: [WorkflowRun]

  public init(visible: [WorkflowRun], history: [WorkflowRun]) {
    self.visible = visible
    self.history = history
  }
}

public enum MenuBarGlyphs {
  private static let progressSteps = 12.0

  public static func glyph(for repo: MenuBarRepo, now: Date) -> MenuBarGlyph? {
    switch RunState.mostUrgent(repo.visible.map(\.state)) {
    case .failed: .failed
    case .running: runningGlyph(repo, now: now)
    case .queued: .queued
    case .passed: .passed
    case .neutral: nil
    }
  }

  public static func glyphs(repos: [MenuBarRepo], signedOut: Bool, now: Date) -> [MenuBarGlyph] {
    if signedOut { return [.signedOut] }
    let active = repos.compactMap { glyph(for: $0, now: now) }.filter {
      $0 != .passed && $0 != .failed
    }
    return active.isEmpty ? [.idle] : active
  }

  private static func runningGlyph(_ repo: MenuBarRepo, now: Date) -> MenuBarGlyph {
    let candidates = repo.visible.filter { $0.state == .running }.map { run in
      let started = run.runStartedAt ?? run.createdAt
      let progress = ETA.estimate(for: run, among: repo.history).map {
        ETA.progress(elapsed: now.timeIntervalSince(started), median: $0.median)
      }
      return (started: started, progress: progress)
    }
    if candidates.contains(where: { $0.progress?.isOverdue == true }) { return .overdue }
    guard let oldest = candidates.min(by: { $0.started < $1.started }),
      let progress = oldest.progress
    else { return .running(progress: nil) }
    return .running(progress: (progress.fraction * progressSteps).rounded() / progressSteps)
  }
}
