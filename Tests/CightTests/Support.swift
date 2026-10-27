import Foundation
import Synchronization
import UserNotifications

@testable import Cight
@testable import CightCore

struct Reply: Sendable {
  var status = 200
  var body = ""
  var error: URLError?
}

struct StubState: Sendable {
  var handler: (@Sendable (URLRequest) async -> Reply)?
  var paths: [String] = []
}

final class Stub: URLProtocol {
  typealias Handler = @Sendable (URLRequest) async -> Reply

  static let state = Mutex(StubState())

  static func install(_ handler: @escaping Handler) {
    state.withLock {
      $0.handler = handler
      $0.paths = []
    }
  }

  static var requestedPaths: [String] { state.withLock { $0.paths } }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    let path = request.url?.path ?? ""
    Self.state.withLock { $0.paths.append(path) }
    let request = self.request
    let handler = Stub.currentHandler()
    nonisolated(unsafe) let me = self
    Task {
      let reply: Reply
      if let handler { reply = await handler(request) } else { reply = Reply(status: 500) }
      Stub.finish(me, request: request, reply: reply)
    }
  }

  static func currentHandler() -> Handler? {
    state.withLock { $0.handler }
  }

  static func finish(_ stub: Stub, request: URLRequest, reply: Reply) {
    if let error = reply.error {
      stub.client?.urlProtocol(stub, didFailWithError: error)
      return
    }
    let url: URL = request.url ?? URL(fileURLWithPath: "/")
    let response = HTTPURLResponse(
      url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: [:])
    if let response {
      stub.client?.urlProtocol(stub, didReceive: response, cacheStoragePolicy: .notAllowed)
    }
    stub.client?.urlProtocol(stub, didLoad: Data(reply.body.utf8))
    stub.client?.urlProtocolDidFinishLoading(stub)
  }

  override func stopLoading() {}
}

func stubbedClient() -> GitHubClient {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [Stub.self]
  return GitHubClient(configuration: configuration, tokenProvider: { "token" })
}

func freshDefaults() -> UserDefaults {
  UserDefaults(suiteName: UUID().uuidString)!
}

let reposJSON = """
  [{"archived":false,"default_branch":"main","full_name":"o/alpha","id":1,"name":"alpha",\
  "owner":{"id":9,"login":"o"},"private":false,"pushed_at":"2026-10-27T18:21:25Z"},\
  {"archived":false,"default_branch":"main","full_name":"o/beta","id":2,"name":"beta",\
  "owner":{"id":9,"login":"o"},"private":false,"pushed_at":"2026-10-27T18:21:25Z"}]
  """

func failedEvent() -> RunEvent {
  let json = """
    {"id":7,"workflow_id":1,"status":"completed","conclusion":"failure","event":"push",\
    "created_at":"2026-10-27T18:00:00Z","run_attempt":1,"head_branch":"main",\
    "actor":{"login":"me","id":1},"triggering_actor":{"login":"me","id":1},\
    "head_repository":{"id":1,"full_name":"o/alpha"}}
    """
  let run = try! JSONDecoder.github.decode(WorkflowRun.self, from: Data(json.utf8))
  return RunEvent(kind: .failed, repo: "o/alpha", run: run)
}

@MainActor
final class FakeCenter: NotificationCentering {
  var status: UNAuthorizationStatus
  var grantsOnRequest: Bool
  private(set) var requests = 0
  private(set) var added: [NotificationContent] = []

  init(status: UNAuthorizationStatus, grantsOnRequest: Bool = true) {
    self.status = status
    self.grantsOnRequest = grantsOnRequest
  }

  func authorizationStatus() async -> UNAuthorizationStatus { status }

  func requestAuthorization() async {
    requests += 1
    status = grantsOnRequest ? .authorized : .denied
  }

  func add(_ content: NotificationContent) async {
    added.append(content)
  }
}
