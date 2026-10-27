import Foundation

public enum MenuBarGlyph: Sendable, Equatable {
  case failed
  case running(progress: Double?)
  case overdue
  case queued
  case passed
  case signedOut
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
  public static func glyph(for repo: MenuBarRepo, now: Date) -> MenuBarGlyph? {
    nil
  }

  public static func glyphs(repos: [MenuBarRepo], signedOut: Bool, now: Date) -> [MenuBarGlyph] {
    []
  }
}
