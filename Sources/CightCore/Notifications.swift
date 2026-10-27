import Foundation

public struct NotificationSettings: Codable, Sendable, Equatable {
  static let key = "notificationSettings"

  public var failed: Bool
  public var fixed: Bool
  public var started: Bool

  public init(failed: Bool = true, fixed: Bool = true, started: Bool = false) {
    self.failed = failed
    self.fixed = fixed
    self.started = started
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
    }
  }
}

public struct NotificationContent: Sendable, Equatable {
  public let identifier: String
  public let title: String
  public let body: String
  public let url: URL?

  public static let signedOut = NotificationContent(
    identifier: "signed-out", title: "Signed out of GitHub",
    body: "Run gh auth login in Terminal to resume monitoring.", url: nil)

  public static func make(for event: RunEvent, settings: NotificationSettings)
    -> NotificationContent?
  {
    guard settings.allows(event.kind) else { return nil }
    let run = event.run
    let headline =
      switch event.kind {
      case .failed: "Failed"
      case .recovered: "Fixed"
      case .started: "Started"
      }
    var body = "\(run.name ?? "Workflow") on \(run.branch)"
    if let actor = run.actor?.login {
      body += " by \(Formatting.login(actor))"
    }
    return NotificationContent(
      identifier: "run-\(run.id)-\(run.runAttempt ?? 1)-\(headline.lowercased())",
      title: "\(headline) in \(event.repo)", body: body, url: run.htmlUrl.flatMap(URL.init))
  }
}
