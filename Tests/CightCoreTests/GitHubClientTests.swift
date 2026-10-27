import Foundation
import Synchronization
import Testing

@testable import CightCore

private final class Counter: Sendable {
  private let value = Mutex(0)
  var count: Int { value.withLock { $0 } }
  func increment() { value.withLock { $0 += 1 } }
}

private func makeClient(
  tokens: [String?] = ["tok"],
  now: Date = t0,
  handler: @escaping @Sendable (URLRequest) -> StubReply
) -> (GitHubClient, Counter) {
  StubProtocol.install(handler)
  let calls = Counter()
  let queue = Mutex(tokens)
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [StubProtocol.self]
  let client = GitHubClient(
    configuration: configuration,
    tokenProvider: {
      calls.increment()
      return queue.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
    },
    now: { now })
  return (client, calls)
}

private func ok(_ fixture: String, headers: [String: String] = [:]) -> StubReply {
  StubReply(status: 200, headers: headers, body: Fixture.data(fixture))
}

@Suite(.serialized)
struct GitHubClientTests {
  @Test func eachRequestHasAFifteenSecondTimeoutAndIgnoresLocalCaches() async throws {
    let (client, _) = makeClient { _ in ok("user") }
    _ = try await client.viewer()
    let request = try #require(StubProtocol.requests.first)
    #expect(request.timeoutInterval == 15)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
  }

  @Test func a200WithoutAnETagEvictsTheOldEntry() async throws {
    let (client, _) = makeClient { request in
      switch StubProtocol.requests.count {
      case 1: ok("runs", headers: ["ETag": "\"abc\""])
      case 2: ok("runs")
      default: ok("runs")
      }
    }
    for _ in 1...3 { _ = try await client.runs(owner: "o", name: "r") }
    #expect(StubProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match") == "\"abc\"")
    #expect(StubProtocol.requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  @Test func a404EvictsTheOldEntry() async throws {
    let (client, _) = makeClient { _ in
      switch StubProtocol.requests.count {
      case 1: ok("runs", headers: ["ETag": "\"abc\""])
      case 2: StubReply(status: 404)
      default: ok("runs")
      }
    }
    _ = try await client.runs(owner: "o", name: "r")
    await #expect(throws: GitHubError.notFound) { try await client.runs(owner: "o", name: "r") }
    _ = try await client.runs(owner: "o", name: "r")
    #expect(StubProtocol.requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  @Test func aChangedTokenClearsTheCache() async throws {
    let (client, _) = makeClient(tokens: ["old", "new"]) { request in
      let bearer = request.value(forHTTPHeaderField: "Authorization")
      switch StubProtocol.requests.count {
      case 1: return ok("runs", headers: ["ETag": "\"abc\""])
      case 2: return StubReply(status: 401)
      default: return bearer == "Bearer new" ? ok("runs") : StubReply(status: 401)
      }
    }
    _ = try await client.runs(owner: "o", name: "r")
    _ = try await client.runs(owner: "o", name: "r")
    #expect(StubProtocol.requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  @Test(arguments: [
    ("a b", "r"), ("o", "r?x=1"), ("o", "r/../x"), ("..", "r"), ("o", "."), ("", "r"),
  ])
  func rejectsOwnersAndNamesThatCannotBePathSegments(owner: String, name: String) async {
    let (client, _) = makeClient { _ in ok("runs") }
    await #expect(throws: GitHubError.notFound) { try await client.runs(owner: owner, name: name) }
    await #expect(throws: GitHubError.notFound) { try await client.repo(owner: owner, name: name) }
    #expect(StubProtocol.requests.isEmpty)
  }

  @Test func acceptsDotsDashesAndUnderscoresInNames() async throws {
    let (client, _) = makeClient { _ in ok("runs") }
    _ = try await client.runs(owner: "Some-Org_1", name: "swift.format-2")
    #expect(
      StubProtocol.requests.first?.url?.path == "/repos/Some-Org_1/swift.format-2/actions/runs")
  }

  @Test func branchesReturnTheNamesFromTheRecordedList() async throws {
    let (client, _) = makeClient { _ in ok("branches") }
    let names = try await client.branches(owner: "swiftlang", name: "swift-format")
    #expect(
      names == [
        "MaxDesiatov-patch-1", "add-post-merge-support",
        "automerge/merge-main-2025-04-18_22-51", "automerge/merge-main-2025-12-15_09-13",
      ])
    #expect(
      StubProtocol.requests.first?.url?.absoluteString
        == "https://api.github.com/repos/swiftlang/swift-format/branches?per_page=100")
  }

  @Test func aFullPageOfBranchesMeansTheListIsIncompleteAndUnknown() async throws {
    let page = (0..<100).map { #"{"name":"b\#($0)"}"# }.joined(separator: ",")
    let (client, _) = makeClient { _ in
      StubReply(status: 200, body: Data("[\(page)]".utf8))
    }
    #expect(try await client.branches(owner: "o", name: "r") == nil)
  }

  @Test func branchesUseTheETagCache() async throws {
    let (client, _) = makeClient { request in
      request.value(forHTTPHeaderField: "If-None-Match") == "\"b1\""
        ? StubReply(status: 304) : ok("branches", headers: ["ETag": "\"b1\""])
    }
    let first = try await client.branches(owner: "o", name: "r")
    let second = try await client.branches(owner: "o", name: "r")
    #expect(first == second)
    #expect(first?.count == 4)
  }

  @Test func sendsRequiredHeaders() async throws {
    let (client, _) = makeClient { _ in ok("user") }
    _ = try await client.viewer()
    let request = try #require(StubProtocol.requests.first)
    #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
  }

  @Test func requestsTheFourEndpoints() async throws {
    let (client, _) = makeClient { request in
      switch request.url?.path {
      case "/user": ok("user")
      case "/user/repos": ok("repos")
      case "/repos/swiftlang/swift-format": ok("repo")
      default: ok("runs")
      }
    }
    #expect(try await client.viewer().login == "octocat")
    #expect(try await client.repos().count == 3)
    #expect(try await client.repo(owner: "swiftlang", name: "swift-format").id == 196_084_046)
    #expect(try await client.runs(owner: "swiftlang", name: "swift-format").count == 10)
    let urls = StubProtocol.requests.compactMap { $0.url?.absoluteString }
    #expect(
      urls == [
        "https://api.github.com/user",
        "https://api.github.com/user/repos?sort=pushed&per_page=100",
        "https://api.github.com/repos/swiftlang/swift-format",
        "https://api.github.com/repos/swiftlang/swift-format/actions/runs?per_page=100",
      ])
  }

  @Test func revalidatesWithETagAndServesTheCachedBodyOn304() async throws {
    let (client, _) = makeClient { request in
      if request.value(forHTTPHeaderField: "If-None-Match") == "\"abc\"" {
        return StubReply(status: 304)
      }
      if StubProtocol.requests.count > 1 { return StubReply(status: 500) }
      return ok("runs", headers: ["ETag": "\"abc\""])
    }
    let first = try await client.runs(owner: "o", name: "r")
    let second = try await client.runs(owner: "o", name: "r")
    #expect(first.count == 10)
    #expect(second == first)
    #expect(StubProtocol.requests.count == 2)
  }

  @Test func etagsAreKeptPerURL() async throws {
    let (client, _) = makeClient { request in
      request.url?.path == "/user"
        ? ok("user", headers: ["ETag": "\"u\""]) : ok("runs", headers: ["ETag": "\"r\""])
    }
    _ = try await client.viewer()
    _ = try await client.runs(owner: "o", name: "r")
    #expect(StubProtocol.requests[1].value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  @Test func reReadsTheTokenOnceOn401AndRetries() async throws {
    let (client, calls) = makeClient(tokens: ["old", "new"]) { request in
      request.value(forHTTPHeaderField: "Authorization") == "Bearer new"
        ? ok("user") : StubReply(status: 401)
    }
    #expect(try await client.viewer().login == "octocat")
    #expect(calls.count == 2)
    #expect(StubProtocol.requests.count == 2)
  }

  @Test func staysUnauthorizedWhenTheNewTokenFailsToo() async {
    let (client, calls) = makeClient(tokens: ["secret-1", "secret-2"]) { _ in
      StubReply(status: 401)
    }
    await #expect(throws: GitHubError.unauthorized) { try await client.viewer() }
    #expect(calls.count == 2)
    #expect(StubProtocol.requests.count == 2)
    #expect(!"\(GitHubError.unauthorized)".contains("secret"))
  }

  @Test func doesNotRetryWhenTheTokenIsUnchanged() async {
    let (client, calls) = makeClient(tokens: ["same"]) { _ in StubReply(status: 401) }
    await #expect(throws: GitHubError.unauthorized) { try await client.viewer() }
    #expect(calls.count == 2)
    #expect(StubProtocol.requests.count == 1)
  }

  @Test func missingTokenIsUnauthorizedWithoutANetworkCall() async {
    let (client, _) = makeClient(tokens: [nil]) { _ in ok("user") }
    await #expect(throws: GitHubError.unauthorized) { try await client.viewer() }
    #expect(StubProtocol.requests.isEmpty)
  }

  @Test(arguments: [403, 429])
  func primaryRateLimitResumesAtTheResetDate(status: Int) async {
    let (client, _) = makeClient { _ in
      StubReply(
        status: status,
        headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": "1700003600"])
    }
    await #expect(throws: GitHubError.rateLimited(resumeAt: at(3600))) {
      try await client.viewer()
    }
  }

  @Test func secondaryRateLimitResumesAfterRetryAfter() async {
    let (client, _) = makeClient { _ in
      StubReply(status: 403, headers: ["retry-after": "90"])
    }
    await #expect(throws: GitHubError.rateLimited(resumeAt: at(90))) {
      try await client.viewer()
    }
  }

  @Test func forbiddenWithQuotaLeftIsNotARateLimit() async {
    let (client, _) = makeClient { _ in
      StubReply(status: 403, headers: ["x-ratelimit-remaining": "42"])
    }
    await #expect(throws: GitHubError.server(403)) { try await client.viewer() }
  }

  @Test func mapsNotFound() async {
    let (client, _) = makeClient { _ in StubReply(status: 404) }
    await #expect(throws: GitHubError.notFound) {
      try await client.repo(owner: "o", name: "gone")
    }
  }

  @Test(arguments: [500, 502, 503])
  func mapsServerErrors(status: Int) async {
    let (client, _) = makeClient { _ in StubReply(status: status) }
    await #expect(throws: GitHubError.server(status)) { try await client.viewer() }
  }

  @Test func mapsTransportErrors() async {
    let (client, _) = makeClient { _ in StubReply(error: URLError(.notConnectedToInternet)) }
    await #expect(throws: GitHubError.transport(.notConnectedToInternet)) {
      try await client.viewer()
    }
  }

  @Test func mapsTimeoutsToTransport() async {
    let (client, _) = makeClient { _ in StubReply(error: URLError(.timedOut)) }
    await #expect(throws: GitHubError.transport(.timedOut)) { try await client.viewer() }
  }

  @Test func mapsUndecodableBodiesToDecoding() async {
    let (client, _) = makeClient { _ in StubReply(body: Data("not json".utf8)) }
    await #expect(throws: GitHubError.decoding) { try await client.viewer() }
  }

  @Test func followsRenamedRepoRedirectsAndKeepsTheToken() async throws {
    let target = "https://api.github.com/repositories/42/actions/runs?per_page=100"
    let (client, _) = makeClient { request in
      request.url?.path.hasPrefix("/repos/old/") == true
        ? StubReply(status: 301, headers: ["Location": target]) : ok("runs")
    }
    let runs = try await client.runs(owner: "old", name: "name")
    #expect(runs.count == 10)
    let last = try #require(StubProtocol.requests.last)
    #expect(last.url?.absoluteString == target)
    #expect(last.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
  }

  @Test func dropsTheTokenWhenRedirectedToAnotherHost() async throws {
    let (client, _) = makeClient { request in
      request.url?.host == "api.github.com"
        ? StubReply(status: 302, headers: ["Location": "https://example.com/x"]) : ok("user")
    }
    _ = try await client.viewer()
    let last = try #require(StubProtocol.requests.last)
    #expect(last.url?.host == "example.com")
    #expect(last.value(forHTTPHeaderField: "Authorization") == nil)
  }
}
