import AppKit
import CightCore
import Foundation
import Observation

@MainActor @Observable
final class RunRowModel: Identifiable {
  let id: Int
  private(set) var workflow: String
  private(set) var pullRequest: Int?
  private(set) var title: String
  private(set) var state: RunState
  private(set) var starter: String
  private(set) var avatar: URL?
  private(set) var url: URL?
  private(set) var startedAt: Date
  private(set) var activityAt: Date
  private(set) var median: TimeInterval?
  private(set) var samples: Int
  private static let workflowWidthCap: CGFloat = 150

  init(run: WorkflowRun, eta: ETAEstimate?) {
    id = run.id
    workflow = run.name ?? "Workflow"
    pullRequest = run.pullRequestNumber
    title = run.displayTitle ?? ""
    state = run.state
    starter = Formatting.login(run.actor?.login ?? "")
    avatar = AvatarCache.url(run.actor?.avatarUrl)
    url = Self.webURL(run.htmlUrl)
    startedAt = run.runStartedAt ?? run.createdAt
    activityAt = run.activityDate
    median = eta?.median
    samples = eta?.sampleCount ?? 0
  }

  func update(run: WorkflowRun, eta: ETAEstimate?) {
    set(\.workflow, run.name ?? "Workflow")
    set(\.pullRequest, run.pullRequestNumber)
    set(\.title, run.displayTitle ?? "")
    set(\.state, run.state)
    set(\.starter, Formatting.login(run.actor?.login ?? ""))
    set(\.avatar, AvatarCache.url(run.actor?.avatarUrl))
    set(\.url, Self.webURL(run.htmlUrl))
    set(\.startedAt, run.runStartedAt ?? run.createdAt)
    set(\.activityAt, run.activityDate)
    set(\.median, eta?.median)
    set(\.samples, eta?.sampleCount ?? 0)
  }

  var workflowWidth: CGFloat {
    let size = NSFont.preferredFont(forTextStyle: .callout).pointSize
    let font = NSFont.systemFont(ofSize: size, weight: .medium)
    let measured = NSAttributedString(string: workflow, attributes: [.font: font]).size().width
    return min(Self.workflowWidthCap, ceil(measured) + 2)
  }

  func progress(at now: Date) -> RunProgress? {
    median.map { ETA.progress(elapsed: now.timeIntervalSince(startedAt), median: $0) }
  }

  private func set<Value: Equatable>(
    _ path: ReferenceWritableKeyPath<RunRowModel, Value>, _ value: Value
  ) {
    if self[keyPath: path] != value { self[keyPath: path] = value }
  }

  private static func webURL(_ string: String?) -> URL? {
    guard let string, let url = URL(string: string), url.scheme == "https",
      url.host == "github.com"
    else { return nil }
    return url
  }
}

struct BranchModel: Identifiable, Equatable {
  let name: String
  let rows: [RunRowModel]

  var id: String { name }

  static func == (lhs: BranchModel, rhs: BranchModel) -> Bool {
    lhs.name == rhs.name && lhs.rows.elementsEqual(rhs.rows, by: ===)
  }
}

enum RepoProblem: Equatable {
  case gone
}

@MainActor @Observable
final class RepoModel: Identifiable {
  let id: String
  let owner: String
  let name: String
  var glyph: MenuBarGlyph?
  var newest: Date?
  var branches: [BranchModel] = []
  var problem: RepoProblem?
  var userExpanded: Bool?

  init(owner: String, name: String) {
    id = "\(owner)/\(name)".lowercased()
    self.owner = owner
    self.name = name
  }

  var hasActiveRun: Bool {
    branches.contains { $0.rows.contains { $0.state == .running || $0.state == .queued } }
  }

  var expanded: Bool {
    RepoCardRules.isExpanded(
      hasActiveRun: hasActiveRun, userChoice: userExpanded, hasProblem: problem != nil)
  }

  func toggle() {
    userExpanded = !expanded
  }
}
