import Foundation

public enum GitHubError: Error, Equatable, Sendable {
  case unauthorized
  case rateLimited(resumeAt: Date)
  case notFound
  case server(Int)
  case transport(URLError.Code)
  case decoding
}

public actor GitHubClient {
  private static let baseURL = "https://api.github.com/"
  private static let apiHost = "api.github.com"
  private static let timeout: TimeInterval = 15
  private static let pageSize = 100

  private let session: URLSession
  private let tokenProvider: @Sendable () async -> String?
  private let now: @Sendable () -> Date
  private var token: String?
  private var cache: [URL: (etag: String, body: Data)] = [:]

  public init(
    configuration: URLSessionConfiguration = .ephemeral,
    tokenProvider: @escaping @Sendable () async -> String?,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    let hardened = configuration.copy() as! URLSessionConfiguration
    hardened.urlCache = nil
    hardened.requestCachePolicy = .reloadIgnoringLocalCacheData
    hardened.timeoutIntervalForRequest = Self.timeout
    self.session = URLSession(configuration: hardened)
    self.tokenProvider = tokenProvider
    self.now = now
  }

  public func viewer() async throws -> Viewer {
    try await get("user")
  }

  public func repos() async throws -> [Repo] {
    try await get("user/repos?sort=pushed&per_page=100")
  }

  public func repo(owner: String, name: String) async throws -> Repo {
    try await get("repos/\(try segment(owner))/\(try segment(name))")
  }

  public func runs(owner: String, name: String) async throws -> [WorkflowRun] {
    let path = "repos/\(try segment(owner))/\(try segment(name))/actions/runs?per_page=100"
    let page: RunsPage = try await get(path)
    return page.runs
  }

  public func branches(owner: String, name: String) async throws -> Set<String>? {
    let path = "repos/\(try segment(owner))/\(try segment(name))/branches?per_page=100"
    let page: [Branch] = try await get(path)
    return page.count < Self.pageSize ? Set(page.map(\.name)) : nil
  }

  private func segment(_ value: String) throws -> String {
    guard RepoPath.isValidSegment(value) else { throw GitHubError.notFound }
    return value
  }

  private func get<Value: Decodable>(_ path: String) async throws -> Value {
    guard let url = URL(string: Self.baseURL + path) else { throw GitHubError.notFound }
    let body = try await body(for: url)
    do {
      return try JSONDecoder.github.decode(Value.self, from: body)
    } catch {
      throw GitHubError.decoding
    }
  }

  private func body(for url: URL) async throws -> Data {
    guard let current = await currentToken() else { throw GitHubError.unauthorized }
    do {
      return try await fetch(url, token: current)
    } catch GitHubError.unauthorized {
      guard let renewed = await renewedToken(), renewed != current else {
        throw GitHubError.unauthorized
      }
      return try await fetch(url, token: renewed)
    }
  }

  private func currentToken() async -> String? {
    if let token { return token }
    token = await tokenProvider()
    return token
  }

  private func renewedToken() async -> String? {
    token = await tokenProvider()
    cache = [:]
    return token
  }

  private func fetch(_ url: URL, token: String) async throws -> Data {
    var request = URLRequest(
      url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
    request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
    request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    request.setValue("cight", forHTTPHeaderField: "User-Agent")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let cached = cache[url] {
      request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(
        for: request, delegate: RedirectPolicy(token: token, apiHost: Self.apiHost))
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as URLError {
      throw GitHubError.transport(error.code)
    }
    guard let http = response as? HTTPURLResponse else { throw GitHubError.decoding }

    switch http.statusCode {
    case 200..<300:
      cache[url] = http.value(forHTTPHeaderField: "ETag").map { ($0, data) }
      return data
    case 304:
      guard let cached = cache[url] else { throw GitHubError.server(304) }
      return cached.body
    case 401:
      throw GitHubError.unauthorized
    case 404:
      cache[url] = nil
      throw GitHubError.notFound
    case 403, 429:
      if let resumeAt = rateLimitResume(http) { throw GitHubError.rateLimited(resumeAt: resumeAt) }
      throw GitHubError.server(http.statusCode)
    default:
      throw GitHubError.server(http.statusCode)
    }
  }

  private func rateLimitResume(_ response: HTTPURLResponse) -> Date? {
    if let retryAfter = response.value(forHTTPHeaderField: "retry-after").flatMap(TimeInterval.init)
    {
      return now().addingTimeInterval(retryAfter)
    }
    if response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
      let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init)
    {
      return Date(timeIntervalSince1970: reset)
    }
    return nil
  }
}

private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
  private let token: String
  private let apiHost: String

  init(token: String, apiHost: String) {
    self.token = token
    self.apiHost = apiHost
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    var redirected = request
    if request.url?.scheme == "https", request.url?.host == apiHost {
      redirected.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    } else {
      redirected.setValue(nil, forHTTPHeaderField: "Authorization")
    }
    return redirected
  }
}
