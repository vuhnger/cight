import Foundation
import Testing

@testable import CightCore

private func lockURL() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent("cight-\(UUID().uuidString).lock")
}

@Suite(.serialized)
struct InstanceLockTests {
  @Test func onlyOneHolderAtATime() throws {
    let url = lockURL()
    let first = try #require(InstanceLock.acquire(at: url))
    #expect(InstanceLock.acquire(at: url) == nil)
    first.release()
    let second = InstanceLock.acquire(at: url)
    #expect(second != nil)
    second?.release()
  }

  @Test func exactlyOneOfManyRacersWins() async {
    let url = lockURL()
    let winners = await withTaskGroup(of: InstanceLock?.self) { group in
      for _ in 0..<24 { group.addTask { InstanceLock.acquire(at: url) } }
      var held: [InstanceLock] = []
      for await lock in group { if let lock { held.append(lock) } }
      return held
    }
    #expect(winners.count == 1)
    for winner in winners { winner.release() }
  }

  @Test func waitingAcquiresOnceTheHolderReleases() throws {
    let url = lockURL()
    let holder = try #require(InstanceLock.acquire(at: url))
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { holder.release() }
    let waited = InstanceLock.acquire(at: url, timeout: 3)
    #expect(waited != nil)
    waited?.release()
  }

  @Test func waitingGivesUpAfterTheTimeout() throws {
    let url = lockURL()
    let holder = try #require(InstanceLock.acquire(at: url))
    let started = Date()
    #expect(InstanceLock.acquire(at: url, timeout: 0.3) == nil)
    #expect(Date().timeIntervalSince(started) >= 0.3)
    holder.release()
  }

  @Test func createsMissingDirectories() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("nested/cight.lock")
    let lock = try #require(InstanceLock.acquire(at: url))
    lock.release()
  }
}

struct StartupPlanTests {
  @Test func theLockWinnerAlwaysRuns() {
    for agent in [true, false] {
      for waits in [true, false] {
        #expect(
          StartupPlan.decide(lockAcquired: true, startedByAgent: agent, waitsForLock: waits)
            == .run)
      }
    }
  }

  @Test func anAgentCopyAsksAPlainHolderToQuitAndTakesOver() {
    #expect(
      StartupPlan.decide(lockAcquired: false, startedByAgent: true, waitsForLock: false)
        == .takeOver(askHolderToQuit: true))
  }

  @Test func aWaitingCopyTakesOverWithoutAskingTheHolder() {
    #expect(
      StartupPlan.decide(lockAcquired: false, startedByAgent: false, waitsForLock: true)
        == .takeOver(askHolderToQuit: false))
  }

  @Test func aPlainSecondLaunchExits() {
    #expect(
      StartupPlan.decide(lockAcquired: false, startedByAgent: false, waitsForLock: false)
        == .exit)
  }

  @Test func onlyAPlainHolderYieldsToTheAgent() {
    #expect(HandoverPolicy.holderShouldYield(startedByAgent: false))
    #expect(!HandoverPolicy.holderShouldYield(startedByAgent: true))
  }

  @Test func detectsTheWaitArgument() {
    #expect(LaunchAgent.waitsForLock(arguments: ["Cight", "--wait-for-lock"]))
    #expect(!LaunchAgent.waitsForLock(arguments: ["Cight"]))
    #expect(!LaunchAgent.waitsForLock(arguments: ["--wait-for-lock"]))
  }
}
