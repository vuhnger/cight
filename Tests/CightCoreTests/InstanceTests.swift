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
    let attempt = InstanceLock.acquire(at: url, timeout: 0.3)
    #expect(attempt.lock == nil)
    #expect(attempt.outcome == .held)
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
}

struct StartupPlanTests {
  private func plan(_ lock: LockOutcome, waits: Bool = false, enabled: Bool = false) -> StartupPlan
  {
    StartupPlan.decide(lock: lock, waits: waits, agentEnabled: enabled)
  }

  @Test func aLockErrorAlwaysFailsAndNeverTouchesAnotherInstance() {
    for waits in [true, false] {
      for enabled in [true, false] {
        #expect(plan(.failed, waits: waits, enabled: enabled) == .exitFailure)
      }
    }
  }

  @Test func aWaitingLaunchRunsOrWaitsEvenWhileTheAgentIsRegistered() {
    for enabled in [true, false] {
      #expect(plan(.acquired, waits: true, enabled: enabled) == .run)
      #expect(plan(.held, waits: true, enabled: enabled) == .waitForLock)
    }
  }

  @Test func aPlainLaunchKicksTheRegisteredAgent() {
    #expect(plan(.acquired, enabled: true) == .kickstartThenExit)
    #expect(plan(.held, enabled: true) == .kickstartThenExit)
  }

  @Test func aPlainLaunchWithoutTheAgentRunsOrExitsQuietly() {
    #expect(plan(.acquired) == .run)
    #expect(plan(.held) == .exitQuietly)
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

struct LoginItemTests {
  @Test func onlyEnabledCountsAsOn() {
    #expect(LoginItemPresentation(status: .enabled).isOn)
    #expect(!LoginItemPresentation(status: .requiresApproval).isOn)
    #expect(!LoginItemPresentation(status: .notRegistered).isOn)
    #expect(!LoginItemPresentation(status: .notFound).isOn)
  }

  @Test func approvalOffersTheSystemSettingsButton() {
    #expect(LoginItemPresentation(status: .requiresApproval).offersSystemSettings)
    #expect(!LoginItemPresentation(status: .enabled).offersSystemSettings)
  }

  @Test func notFoundHasItsOwnMessage() {
    let missing = LoginItemPresentation(status: .notFound)
    #expect(missing.message != nil)
    #expect(missing.message != LoginItemPresentation(status: .requiresApproval).message)
    #expect(!missing.offersSystemSettings)
    #expect(LoginItemPresentation(status: .enabled).message == nil)
  }
}

struct LaunchAgentPlistTests {
  private func load() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Resources/LaunchAgent/com.vuhnger.cight.agent.plist")
    return try #require(
      try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        as? [String: Any])
  }

  @Test func startsTheBundledExecutableAtLoad() throws {
    let plist = try load()
    #expect(plist["Label"] as? String == "com.vuhnger.cight.agent")
    #expect(plist["BundleProgram"] as? String == "Contents/MacOS/Cight")
    #expect(plist["RunAtLoad"] as? Bool == true)
  }

  @Test func restartsOnlyAfterANonZeroExit() throws {
    let keepAlive = try #require(try load()["KeepAlive"] as? [String: Any])
    #expect(keepAlive["SuccessfulExit"] as? Bool == false)
  }
}
