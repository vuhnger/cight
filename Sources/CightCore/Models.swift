import Foundation

extension JSONDecoder {
  static var github: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }
}

public struct Viewer: Decodable, Sendable, Equatable {
  public let id: Int
  public let login: String
}

public struct Repo: Decodable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let name: String
  public let fullName: String
  public let defaultBranch: String
  public let pushedAt: Date?
}

public struct Account: Decodable, Sendable, Equatable {
  public let id: Int?
  public let login: String
}

public struct RepoRef: Decodable, Sendable, Equatable {
  public let id: Int
  public let fullName: String?
}

public struct WorkflowRun: Decodable, Sendable, Equatable, Identifiable {
  public let id: Int
  public let workflowId: Int
  public let createdAt: Date
  public let name: String?
  public let status: String?
  public let conclusion: String?
  public let event: String?
  public let headBranch: String?
  public let headSha: String?
  public let runNumber: Int?
  public let runAttempt: Int?
  public let runStartedAt: Date?
  public let updatedAt: Date?
  public let htmlUrl: String?
  public let actor: Account?
  public let triggeringActor: Account?
  public let headRepository: RepoRef?

  public var state: RunState {
    RunState(status: status, conclusion: conclusion)
  }

  public var branch: String {
    headBranch ?? "unknown"
  }

  public var activityDate: Date {
    updatedAt ?? createdAt
  }
}

public struct RunsPage: Decodable, Sendable {
  public let runs: [WorkflowRun]

  private enum CodingKeys: String, CodingKey {
    case workflowRuns
  }

  private struct Lossy<Element: Decodable>: Decodable {
    let value: Element?
    init(from decoder: any Decoder) throws {
      value = try? decoder.singleValueContainer().decode(Element.self)
    }
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    runs = try container.decode([Lossy<WorkflowRun>].self, forKey: .workflowRuns).compactMap(
      \.value)
  }
}

public enum RunState: Sendable, Equatable, CaseIterable {
  case failed
  case running
  case queued
  case passed
  case neutral

  public init(status: String?, conclusion: String?) {
    switch status {
    case "in_progress":
      self = .running
    case "queued", "waiting", "requested", "pending":
      self = .queued
    case "completed":
      switch conclusion {
      case "success": self = .passed
      case "failure", "timed_out", "startup_failure": self = .failed
      case "action_required": self = .queued
      default: self = .neutral
      }
    default:
      self = .neutral
    }
  }

  public var urgency: Int {
    Self.allCases.firstIndex(of: self) ?? Self.allCases.count
  }

  public static func mostUrgent(_ states: [RunState]) -> RunState {
    states.min { $0.urgency < $1.urgency } ?? .neutral
  }
}
