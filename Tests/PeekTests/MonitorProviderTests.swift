import Foundation
import Testing

@testable import Peek
@testable import PeekCore

private struct FakeProvider: RunProvider {
  let host: String
  let repo: Repo
  let runId: Int
  var failure: GitHubError?

  func viewer() async throws -> Viewer {
    if let failure { throw failure }
    return Viewer(id: 1, login: "me")
  }

  func repos() async throws -> [Repo] { [repo] }

  func latestRun(repo: Repo, actor: String, since: Date) async throws -> WorkflowRun? {
    try run(for: repo)
  }

  func runs(repo: Repo) async throws -> [WorkflowRun] { [try run(for: repo)] }

  func branches(repo: Repo) async throws -> Set<String>? { nil }

  private func run(for repo: Repo) throws -> WorkflowRun {
    let json = """
      {"id":\(runId),"workflow_id":1,"status":"completed","conclusion":"success","event":"push",\
      "created_at":"\(Date().ISO8601Format())","head_branch":"main","run_attempt":1,\
      "actor":{"login":"me","id":1},\
      "head_repository":{"id":\(repo.id),"full_name":"\(repo.fullName)"}}
      """
    return try JSONDecoder.github.decode(WorkflowRun.self, from: Data(json.utf8))
  }
}

private func repo(host: String, id: Int = 1) -> Repo {
  Repo(
    id: id, name: "bar", fullName: "foo/bar", defaultBranch: "main", pushedAt: Date(), host: host)
}

@MainActor
struct MonitorProviderTests {
  @Test func aFailingGitLabHostLeavesGitHubResultsIntact() async {
    for failure in [GitHubError.unauthorized, .transport(.timedOut), .server(500), .decoding] {
      let monitor = Monitor(
        github: FakeProvider(host: Repo.githubHost, repo: repo(host: Repo.githubHost), runId: 5),
        gitLab: {
          [
            FakeProvider(
              host: "gitlab.example.com", repo: repo(host: "gitlab.example.com"), runId: 5,
              failure: failure)
          ]
        })
      await monitor.pollOnce()
      #expect(monitor.repos.map(\.id) == ["foo/bar"])
      #expect(monitor.repos.first?.branches.first?.rows.count == 1)
      #expect(monitor.glyphs != [.signedOut])
      let expected: PanelNotice? = failure == .unauthorized ? .gitLabSignedOut : nil
      #expect(monitor.notice == expected)
    }
  }

  @Test func aFailingGitHubLeavesGitLabCardsInPlace() async {
    let monitor = Monitor(
      github: FakeProvider(
        host: Repo.githubHost, repo: repo(host: Repo.githubHost), runId: 5,
        failure: .transport(.notConnectedToInternet)),
      gitLab: {
        [FakeProvider(host: "gitlab.com", repo: repo(host: "gitlab.com"), runId: 5)]
      })
    await monitor.pollOnce()
    #expect(monitor.repos.map(\.id) == ["gitlab.com/foo/bar"])
  }

  @Test func sameNameAndSameIdsOnTwoHostsGiveTwoCardsWithTheirOwnRows() async {
    let monitor = Monitor(
      github: FakeProvider(host: Repo.githubHost, repo: repo(host: Repo.githubHost), runId: 5),
      gitLab: {
        [
          FakeProvider(host: "gitlab.com", repo: repo(host: "gitlab.com"), runId: 5),
          FakeProvider(
            host: "gitlab.example.com", repo: repo(host: "gitlab.example.com"), runId: 5),
        ]
      })
    await monitor.pollOnce()
    let ids = Set(monitor.repos.map(\.id))
    #expect(ids == ["foo/bar", "gitlab.com/foo/bar", "gitlab.example.com/foo/bar"])
    let rows = monitor.repos.compactMap { $0.branches.first?.rows.first }
    #expect(rows.count == 3)
    #expect(Set(rows.map(ObjectIdentifier.init)).count == 3)
  }

  @Test func aGitLabSignOutReportsOnItsOwnSessionChannel() async {
    let monitor = Monitor(
      github: FakeProvider(host: Repo.githubHost, repo: repo(host: Repo.githubHost), runId: 5),
      gitLab: {
        [
          FakeProvider(
            host: "gitlab.com", repo: repo(host: "gitlab.com"), runId: 5, failure: .unauthorized)
        ]
      })
    var github: [SessionState] = []
    var gitlab: [SessionState] = []
    monitor.onSession = { github.append($0) }
    monitor.onGitLabSession = { gitlab.append($0) }
    await monitor.pollOnce()
    #expect(github.last == .signedIn)
    #expect(gitlab.last == .signedOut)
  }

  @Test func withoutGitLabHostsOnlyGitHubRuns() async {
    let monitor = Monitor(
      github: FakeProvider(host: Repo.githubHost, repo: repo(host: Repo.githubHost), runId: 5),
      gitLab: { [] })
    var gitlab: [SessionState] = []
    monitor.onGitLabSession = { gitlab.append($0) }
    await monitor.pollOnce()
    #expect(monitor.repos.map(\.id) == ["foo/bar"])
    #expect(gitlab.allSatisfy { $0 == .unknown })
    #expect(monitor.notice == nil)
  }
}
