import Foundation
import Testing

@testable import CightCore

struct LaunchAgentPlistTests {
  private func parse(_ data: Data) throws -> [String: Any] {
    try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  @Test func startsTheGivenExecutableAtLoadWithTheAgentArgument() throws {
    let plist = try parse(LaunchAgentPlist.render(program: "/Apps/Cight.app/Contents/MacOS/Cight"))
    #expect(plist["Label"] as? String == "com.vuhnger.cight")
    #expect(
      plist["ProgramArguments"] as? [String] == [
        "/Apps/Cight.app/Contents/MacOS/Cight", "--launch-agent",
      ])
    #expect(plist["RunAtLoad"] as? Bool == true)
  }

  @Test func restartsOnlyAfterANonZeroExit() throws {
    let plist = try parse(LaunchAgentPlist.render(program: "/x"))
    let keepAlive = try #require(plist["KeepAlive"] as? [String: Any])
    #expect(keepAlive["SuccessfulExit"] as? Bool == false)
  }

  @Test func readsTheProgramBack() {
    #expect(
      LaunchAgentPlist.program(in: LaunchAgentPlist.render(program: "/a b/Cight")) == "/a b/Cight")
    #expect(LaunchAgentPlist.program(in: Data("nope".utf8)) == nil)
    #expect(LaunchAgentPlist.program(in: Data()) == nil)
  }
}

struct StartupPlanTests {
  @Test func aLoneInstanceRuns() {
    #expect(StartupPlan.decide(me: 10, others: [], byLaunchd: false) == .run)
    #expect(StartupPlan.decide(me: 10, others: [], byLaunchd: true) == .run)
  }

  @Test func aPlainLaunchYieldsToAnOlderInstance() {
    #expect(StartupPlan.decide(me: 10, others: [4], byLaunchd: false) == .yield)
    #expect(StartupPlan.decide(me: 10, others: [11, 4], byLaunchd: false) == .yield)
  }

  @Test func aPlainLaunchRunsWhenItIsTheOldest() {
    #expect(StartupPlan.decide(me: 10, others: [11, 12], byLaunchd: false) == .run)
  }

  @Test func theLowestOfManyRacersIsTheOnlySurvivor() {
    let pids: [Int32] = [30, 12, 21, 18, 40, 25]
    let survivors = pids.filter { me in
      StartupPlan.decide(me: me, others: pids.filter { $0 != me }, byLaunchd: false) == .run
    }
    #expect(survivors == [12])
  }

  @Test func aLaunchdLaunchWaitsForAnyOtherInstance() {
    #expect(StartupPlan.decide(me: 10, others: [4], byLaunchd: true) == .waitForOthers)
    #expect(StartupPlan.decide(me: 10, others: [11], byLaunchd: true) == .waitForOthers)
  }
}

struct KickstartPlanTests {
  @Test func aPlainLaunchHandsOverToALoadedAgent() {
    #expect(
      StartupPlan.decide(me: 10, others: [], byLaunchd: false, agentLoaded: true) == .kickstart)
    #expect(
      StartupPlan.decide(me: 10, others: [11], byLaunchd: false, agentLoaded: true) == .kickstart)
  }

  @Test func anOlderInstanceStillWinsOverAKickstart() {
    #expect(StartupPlan.decide(me: 10, others: [4], byLaunchd: false, agentLoaded: true) == .yield)
  }

  @Test func theLaunchdCopyNeverKicksItself() {
    #expect(StartupPlan.decide(me: 10, others: [], byLaunchd: true, agentLoaded: true) == .run)
  }
}
