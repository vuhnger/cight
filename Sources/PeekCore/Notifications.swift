import Foundation

public struct NotificationSettings: Codable, Sendable, Equatable {
  static let key = "notificationSettings"

  public var failed: Bool
  public var fixed: Bool
  public var started: Bool
  public var passed: Bool

  public init(
    failed: Bool = true, fixed: Bool = true, started: Bool = false, passed: Bool = true
  ) {
    self.failed = failed
    self.fixed = fixed
    self.started = started
    self.passed = passed
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    failed = try container.decode(Bool.self, forKey: .failed)
    fixed = try container.decode(Bool.self, forKey: .fixed)
    started = try container.decode(Bool.self, forKey: .started)
    passed = try container.decodeIfPresent(Bool.self, forKey: .passed) ?? true
  }

  public static func load(from defaults: UserDefaults) -> NotificationSettings {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
      ?? NotificationSettings()
  }

  public func save(to defaults: UserDefaults) {
    defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
  }

  func allows(_ kind: RunEvent.Kind) -> Bool {
    switch kind {
    case .failed: failed
    case .recovered: fixed
    case .started: started
    case .passed: passed
    }
  }
}

public enum ToastGlyph: Sendable, Equatable {
  case passed
  case failed
  case running
  case signedOut
}

public enum ToastStack {
  public static let limit = 3

  public static func pushing<T>(_ toast: T, onto stack: [T]) -> [T] {
    Array(([toast] + stack).prefix(limit))
  }
}

public struct ToastContent: Sendable, Equatable {
  public let glyph: ToastGlyph
  public let line1: String
  public let line2: String
  public let pullRequest: Int?
  public let url: URL?
  public var isMergeRequest = false

  public static let gitLabSignedOut = ToastContent(
    glyph: .signedOut, line1: "Signed out of GitLab",
    line2: "Run glab auth login in Terminal to resume monitoring.", pullRequest: nil, url: nil)

  public static let signedOut = ToastContent(
    glyph: .signedOut, line1: "Signed out of GitHub",
    line2: "Run gh auth login in Terminal to resume monitoring.", pullRequest: nil, url: nil)

  public static func make(for event: RunEvent, settings: NotificationSettings) -> ToastContent? {
    guard settings.allows(event.kind) else { return nil }
    let run = event.run
    let (glyph, verb) =
      switch event.kind {
      case .failed: (ToastGlyph.failed, "failed")
      case .recovered: (.passed, "fixed")
      case .started: (.running, "started")
      case .passed: (.passed, "passed")
      }
    return ToastContent(
      glyph: glyph, line1: event.repo, line2: "\(run.name ?? "Workflow") \(verb) on \(run.branch)",
      pullRequest: run.pullRequestNumber, url: run.link(host: event.host),
      isMergeRequest: run.isMergeRequest == true)
  }
}
