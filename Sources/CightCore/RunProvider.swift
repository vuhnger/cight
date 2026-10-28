import Foundation

public protocol RunProvider: Sendable {
  func viewer() async throws -> Viewer
  func repos() async throws -> [Repo]
  func latestRun(owner: String, name: String, actor: String, since: Date) async throws
    -> WorkflowRun?
  func runs(owner: String, name: String) async throws -> [WorkflowRun]
  func branches(owner: String, name: String) async throws -> Set<String>?
}
