import Foundation
import Testing

@testable import Cight
@testable import CightCore

@MainActor
struct RunRowModelTests {
  private func run(pullRequests: String?) throws -> WorkflowRun {
    let extra = pullRequests.map { ", \"pull_requests\": \($0)" } ?? ""
    let json = """
      {"id": 1, "workflow_id": 2, "name": "CI", "run_number": 49,
       "created_at": "2026-10-27T20:59:22Z"\(extra)}
      """
    return try JSONDecoder.github.decode(WorkflowRun.self, from: Data(json.utf8))
  }

  @Test func showsThePullRequestNumberNotTheRunNumber() throws {
    let row = RunRowModel(run: try run(pullRequests: "[{\"number\": 7}]"), eta: nil)
    #expect(row.pullRequest == 7)
  }

  @Test func showsNothingWithoutAPullRequest() throws {
    #expect(RunRowModel(run: try run(pullRequests: "[]"), eta: nil).pullRequest == nil)
    #expect(RunRowModel(run: try run(pullRequests: nil), eta: nil).pullRequest == nil)
  }

  @Test func updatingFollowsTheNewRun() throws {
    let row = RunRowModel(run: try run(pullRequests: nil), eta: nil)
    row.update(run: try run(pullRequests: "[{\"number\": 12}]"), eta: nil)
    #expect(row.pullRequest == 12)
  }
}
