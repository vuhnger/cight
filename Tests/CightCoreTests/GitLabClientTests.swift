import Foundation
import Synchronization
import Testing

@testable import CightCore

private final class LabStub: URLProtocol {
  static let handler = Mutex<(@Sendable (URLRequest) -> StubReply)?>(nil)
  static let seen = Mutex<[URLRequest]>([])

  static func install(_ handler: @escaping @Sendable (URLRequest) -> StubReply) {
    Self.handler.withLock { $0 = handler }
    seen.withLock { $0 = [] }
  }

  static var requests: [URLRequest] { seen.withLock { $0 } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.seen.withLock { $0.append(request) }
    guard let reply = Self.handler.withLock({ $0 })?(request) else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    if let error = reply.error {
      client?.urlProtocol(self, didFailWithError: error)
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
      headerFields: reply.headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: reply.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

private func makeClient(
  host: String = "gitlab.example.com",
  token: String? = "tok",
  handler: @escaping @Sendable (URLRequest) -> StubReply
) -> GitLabClient {
  LabStub.install(handler)
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [LabStub.self]
  return GitLabClient(
    host: host, configuration: configuration, tokenProvider: { token }, now: { t0 })
}

private func reply(_ fixture: String, headers: [String: String] = [:]) -> StubReply {
  StubReply(status: 200, headers: headers, body: Fixture.data(fixture))
}

private let mine = """
  [{"id":9003,"project_id":101,"status":"running","created_at":"2026-10-27T18:00:00.100Z"}]
  """

private func route(_ request: URLRequest) -> StubReply {
  let path = request.url?.path ?? ""
  let query = request.url?.query ?? ""
  switch path {
  case "/api/v4/user": return reply("gitlab-user")
  case "/api/v4/projects": return reply("gitlab-projects")
  case "/api/v4/projects/101/merge_requests": return reply("gitlab-merge-requests")
  case "/api/v4/projects/101/repository/branches": return StubReply(body: Data("[]".utf8))
  case "/api/v4/projects/101/pipelines":
    return query.contains("username=")
      ? StubReply(body: Data(mine.utf8)) : reply("gitlab-pipelines")
  default: return StubReply(status: 404)
  }
}

private let project = Repo(
  id: 101, name: "api", fullName: "acme/platform/api", defaultBranch: "main", pushedAt: t0,
  host: "gitlab.example.com")

@Suite(.serialized)
struct GitLabClientTests {
  @Test(arguments: [
    ("created", RunState.queued), ("waiting_for_resource", .queued), ("preparing", .queued),
    ("pending", .queued), ("scheduled", .queued), ("running", .running), ("success", .passed),
    ("failed", .failed), ("canceled", .neutral), ("skipped", .neutral), ("manual", .neutral),
    ("somethingNew", .neutral),
  ])
  func mapsEveryPipelineStatusToARunState(status: String, expected: RunState) {
    let mapped = GitLabMapping.status(status)
    #expect(RunState(status: mapped.status, conclusion: mapped.conclusion) == expected)
  }

  @Test func canceledMapsLikeAGitHubCancelledRunAndSkippedLikeASkippedOne() {
    #expect(GitLabMapping.status("canceled").conclusion == "cancelled")
    #expect(GitLabMapping.status("manual").conclusion == "cancelled")
    #expect(GitLabMapping.status("skipped").conclusion == "skipped")
  }

  @Test(arguments: [
    ("refs/merge-requests/12/head", 12), ("refs/merge-requests/7/merge", 7),
  ])
  func readsTheMergeRequestNumberFromTheRef(ref: String, number: Int) {
    #expect(GitLabMapping.mergeRequestNumber(ref: ref) == number)
  }

  @Test(arguments: [
    "main", "refs/merge-requests/x/head", "refs/merge-requests/12", "refs/heads/12",
  ])
  func aPlainRefHasNoMergeRequestNumber(ref: String) {
    #expect(GitLabMapping.mergeRequestNumber(ref: ref) == nil)
  }

  @Test func projectsBecomeReposWithTheFullPathAndTheHost() async throws {
    let client = makeClient(handler: route)
    let repos = try await client.repos()
    #expect(repos.map(\.fullName) == ["acme/platform/api", "acme/docs"])
    #expect(repos.map(\.host) == ["gitlab.example.com", "gitlab.example.com"])
    #expect(repos[0].owner == "acme/platform")
    #expect(repos[0].name == "api")
    #expect(repos[1].defaultBranch == "main")
    #expect(repos[0].pushedAt != nil)
    #expect(repos[1].pushedAt != nil)
  }

  @Test func pipelinesBecomeRunsWithNameStateAndLink() async throws {
    let client = makeClient(handler: route)
    let runs = try await client.runs(repo: project)
    let running = try #require(runs.first { $0.id == 9003 })
    let unnamed = try #require(runs.first { $0.id == 9002 })
    #expect(running.name == "Build and test")
    #expect(running.state == .running)
    #expect(running.htmlUrl == "https://gitlab.com/acme/platform/api/-/pipelines/9003")
    #expect(unnamed.name == "Pipeline")
    #expect(unnamed.state == .passed)
    #expect(runs.first { $0.id == 9001 }?.state == .failed)
    #expect(running.pullRequestNumber == nil)
  }

  @Test func aMergeRequestPipelineCarriesTheMergeRequestNumberAndSourceBranch() async throws {
    let client = makeClient { request in
      request.url?.path == "/api/v4/projects/101/pipelines"
        ? reply("gitlab-mr-pipelines") : route(request)
    }
    let run = try #require(try await client.runs(repo: project).first)
    #expect(run.pullRequestNumber == 12)
    #expect(run.isMergeRequest == true)
    #expect(run.branch == "speed-up-cache")
    #expect(run.displayTitle == "Speed up the cache")
    #expect(run.state == .queued)
  }

  @Test func theViewersPipelinesAreMarkedAsTheirs() async throws {
    let client = makeClient(handler: route)
    let runs = try await client.runs(repo: project)
    #expect(runs.first { $0.id == 9003 }?.actor?.login == "vuhnger")
    #expect(runs.first { $0.id == 9002 }?.actor == nil)
  }

  @Test func discoveryAsksForTheViewersPipelinesSinceTheCutoff() async throws {
    let client = makeClient(handler: route)
    let run = try await client.latestRun(repo: project, actor: "vuhnger", since: t0)
    #expect(run?.id == 9003)
    let query = try #require(LabStub.requests.last?.url?.query)
    #expect(query.contains("username=vuhnger"))
    #expect(query.contains("created_after="))
  }

  @Test func everyRequestHasATimeoutBearerTokenAndTheConfiguredHost() async throws {
    let client = makeClient(handler: route)
    _ = try await client.viewer()
    let request = try #require(LabStub.requests.first)
    #expect(request.timeoutInterval == 15)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    #expect(request.url?.host == "gitlab.example.com")
  }

  @Test func anETagIsSentBackAndA304ReusesTheBody() async throws {
    let client = makeClient { _ in
      LabStub.requests.count == 1
        ? reply("gitlab-projects", headers: ["ETag": "\"e1\""]) : StubReply(status: 304)
    }
    let first = try await client.repos()
    let second = try await client.repos()
    #expect(first == second)
    #expect(LabStub.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"e1\"")
  }

  @Test func a401IsUnauthorizedAndNoTokenNeverLeavesTheProcess() async {
    let client = makeClient { _ in StubReply(status: 401) }
    await #expect(throws: GitHubError.unauthorized) { try await client.repos() }
    let missing = makeClient(token: nil) { _ in reply("gitlab-projects") }
    await #expect(throws: GitHubError.unauthorized) { try await missing.repos() }
    #expect(LabStub.requests.isEmpty)
  }

  @Test func a429ResumesAfterRetryAfter() async {
    let client = makeClient { _ in StubReply(status: 429, headers: ["Retry-After": "30"]) }
    await #expect(throws: GitHubError.rateLimited(resumeAt: t0.addingTimeInterval(30))) {
      try await client.repos()
    }
  }

  @Test func aTransportFailureIsReportedNotThrownAsSomethingElse() async {
    let client = makeClient { _ in StubReply(error: URLError(.cannotConnectToHost)) }
    await #expect(throws: GitHubError.transport(.cannotConnectToHost)) { try await client.repos() }
  }
}
