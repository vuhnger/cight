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
    let first = try #require(InstanceLock.acquire(at: url).lock)
    #expect(InstanceLock.acquire(at: url).lock == nil)
    first.release()
    let second = InstanceLock.acquire(at: url).lock
    #expect(second != nil)
    second?.release()
  }

  @Test func exactlyOneOfManyRacersWins() async {
    let url = lockURL()
    let winners = await withTaskGroup(of: InstanceLock?.self) { group in
      for _ in 0..<24 { group.addTask { InstanceLock.acquire(at: url).lock } }
      var held: [InstanceLock] = []
      for await lock in group { if let lock { held.append(lock) } }
      return held
    }
    #expect(winners.count == 1)
    for winner in winners { winner.release() }
  }

  @Test func waitingAcquiresOnceTheHolderReleases() throws {
    let url = lockURL()
    let holder = try #require(InstanceLock.acquire(at: url).lock)
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { holder.release() }
    let waited = InstanceLock.acquire(at: url, timeout: 3).lock
    #expect(waited != nil)
    waited?.release()
  }

  @Test func waitingGivesUpAfterTheTimeout() throws {
    let url = lockURL()
    let holder = try #require(InstanceLock.acquire(at: url).lock)
    let started = Date()
    #expect(InstanceLock.acquire(at: url, timeout: 0.3).lock == nil)
    #expect(Date().timeIntervalSince(started) >= 0.3)
    holder.release()
  }

  @Test func createsMissingDirectories() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathComponent("nested/cight.lock")
    let lock = try #require(InstanceLock.acquire(at: url).lock)
    lock.release()
  }

  @Test func anUnopenableLockFileIsAnErrorNotContention() {
    let directory = FileManager.default.temporaryDirectory
    let attempt = InstanceLock.acquire(at: directory, timeout: 5)
    #expect(attempt.outcome == .failed)
    #expect(attempt.lock == nil)
  }

  @Test func waitingForAHolderSeesOneThatAppearsLate() {
    let url = lockURL()
    nonisolated(unsafe) var started: InstanceLock?
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
      started = InstanceLock.acquire(at: url).lock
    }
    #expect(InstanceLock.waitForHolder(at: url, timeout: 3) == .held)
    started?.release()
  }

  @Test func waitingForAHolderThatNeverComesLeavesTheLockFree() {
    let url = lockURL()
    #expect(InstanceLock.waitForHolder(at: url, timeout: 0.3) == .acquired)
    #expect(InstanceLock.acquire(at: url).outcome == .acquired)
  }

  @Test func contentionIsReportedAsHeld() throws {
    let url = lockURL()
    let holder = try #require(InstanceLock.acquire(at: url).lock)
    #expect(InstanceLock.acquire(at: url).outcome == .held)
    holder.release()
    #expect(InstanceLock.acquire(at: url).outcome == .acquired)
  }
}

struct StartupPlanTests {
  private func plan(
    _ lock: LockOutcome, agent: Bool = false, waits: Bool = false, enabled: Bool = false
  ) -> StartupPlan {
    StartupPlan.decide(
      lock: lock, startedByAgent: agent, waitsForLock: waits, agentEnabled: enabled)
  }

  @Test func aLockErrorAlwaysFailsAndNeverTouchesAnotherInstance() {
    for agent in [true, false] {
      for waits in [true, false] {
        for enabled in [true, false] {
          #expect(plan(.failed, agent: agent, waits: waits, enabled: enabled) == .exitFailure)
        }
      }
    }
  }

  @Test func theAgentChildRunsOrWaitsForTheLock() {
    for enabled in [true, false] {
      #expect(plan(.acquired, agent: true, enabled: enabled) == .run)
      #expect(plan(.held, agent: true, enabled: enabled) == .waitForLock)
    }
  }

  @Test func aWaitingCopyRunsOrWaitsEvenWhileTheAgentIsStillRegistered() {
    for enabled in [true, false] {
      #expect(plan(.acquired, waits: true, enabled: enabled) == .run)
      #expect(plan(.held, waits: true, enabled: enabled) == .waitForLock)
    }
  }

  @Test func aPlainLaunchHandsOverToTheRegisteredAgent() {
    #expect(plan(.acquired, enabled: true) == .kickstartThenExit)
    #expect(plan(.held, enabled: true) == .kickstartThenExit)
  }

  @Test func aPlainLaunchWithoutTheAgentRunsOrExitsQuietly() {
    #expect(plan(.acquired) == .run)
    #expect(plan(.held) == .exitQuietly)
  }

  @Test func detectsTheWaitArgument() {
    #expect(LaunchAgent.waitsForLock(arguments: ["Cight", "--wait-for-lock"]))
    #expect(!LaunchAgent.waitsForLock(arguments: ["Cight"]))
    #expect(!LaunchAgent.waitsForLock(arguments: ["--wait-for-lock"]))
  }
}

struct ReregisterPolicyTests {
  private let current = AgentIdentity(version: "12", binaryHash: "aaa")

  @Test func reregistersWhenTheBuildOrBinaryChanged() {
    #expect(
      ReregisterPolicy.shouldReregister(
        agentEnabled: true, stored: AgentIdentity(version: "11", binaryHash: "aaa"),
        current: current))
    #expect(
      ReregisterPolicy.shouldReregister(
        agentEnabled: true, stored: AgentIdentity(version: "12", binaryHash: "bbb"),
        current: current))
  }

  @Test func reregistersWhenNothingWasStored() {
    #expect(ReregisterPolicy.shouldReregister(agentEnabled: true, stored: nil, current: current))
  }

  @Test func leavesAMatchingRegistrationAlone() {
    #expect(
      !ReregisterPolicy.shouldReregister(agentEnabled: true, stored: current, current: current))
  }

  @Test func neverRegistersWhatTheUserDidNotEnable() {
    #expect(!ReregisterPolicy.shouldReregister(agentEnabled: false, stored: nil, current: current))
  }

  @Test func theIdentityRoundTripsThroughDefaults() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    #expect(AgentIdentity.load(from: defaults) == nil)
    current.save(to: defaults)
    #expect(AgentIdentity.load(from: defaults) == current)
  }
}
