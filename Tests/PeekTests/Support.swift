import Foundation

@testable import Peek
@testable import PeekCore

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
