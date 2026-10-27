import Foundation
import Synchronization
import UserNotifications

@testable import Cight
@testable import CightCore

func freshDefaults() -> UserDefaults {
  UserDefaults(suiteName: UUID().uuidString)!
}

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
