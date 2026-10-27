import Foundation
import Testing

@testable import CightCore

struct UserMessageTests {
  @Test func everyErrorHasADistinctActionableMessage() {
    let errors: [GitHubError] = [
      .unauthorized, .rateLimited(resumeAt: at(300)), .notFound, .server(502),
      .transport(.notConnectedToInternet), .decoding,
    ]
    let texts = errors.map { UserMessage.text(for: $0, now: t0) }
    #expect(Set(texts).count == errors.count)
    #expect(texts.allSatisfy { !$0.isEmpty })
  }

  @Test func signedOutMessageNamesTheCLIAndTheLoginCommand() {
    let text = UserMessage.text(for: .unauthorized, now: t0)
    #expect(text.contains("gh auth login"))
  }

  @Test func rateLimitMessageSaysHowLongToWait() {
    #expect(UserMessage.text(for: .rateLimited(resumeAt: at(300)), now: t0).contains("5m 0s"))
  }

  @Test func serverMessageNamesTheStatus() {
    #expect(UserMessage.text(for: .server(502), now: t0).contains("502"))
  }

  @Test func addResultsExplainThemselvesExceptSuccess() {
    let added = WatchedRepo(owner: "a", name: "b", defaultBranch: "main", filter: .mine)
    #expect(UserMessage.text(for: .added(added), now: t0) == nil)
    #expect(UserMessage.text(for: .duplicate, now: t0) == "Already watched.")
    #expect(UserMessage.text(for: .full, now: t0)?.contains("8") == true)
    #expect(UserMessage.text(for: .invalidInput, now: t0)?.contains("owner/repo") == true)
    #expect(
      UserMessage.text(for: .failed(.notFound), now: t0)
        == UserMessage.text(for: .notFound, now: t0))
  }

  @Test func noMessageUsesEmDashesOrMiddleDots() {
    let banned: [Character] = ["\u{2014}", "\u{00B7}"]
    let errors: [GitHubError] = [
      .unauthorized, .rateLimited(resumeAt: at(90)), .notFound, .server(500),
      .transport(.timedOut), .decoding,
    ]
    for error in errors {
      #expect(!UserMessage.text(for: error, now: t0).contains(where: banned.contains))
    }
  }
}

struct LaunchPolicyTests {
  @Test func aUserLaunchAlwaysOpensSettings() {
    #expect(SettingsLaunchPolicy.shouldOpen(startedByLaunchAgent: false, watchedCount: 3))
    #expect(SettingsLaunchPolicy.shouldOpen(startedByLaunchAgent: false, watchedCount: 0))
  }

  @Test func anAgentLaunchOpensSettingsOnlyWhenNothingIsWatched() {
    #expect(!SettingsLaunchPolicy.shouldOpen(startedByLaunchAgent: true, watchedCount: 2))
    #expect(SettingsLaunchPolicy.shouldOpen(startedByLaunchAgent: true, watchedCount: 0))
  }

  @Test func recognisesAnAgentStartByTheLaunchdServiceName() {
    #expect(LaunchAgent.isStartedByAgent(environment: ["XPC_SERVICE_NAME": LaunchAgent.label]))
    #expect(
      !LaunchAgent.isStartedByAgent(environment: [
        "XPC_SERVICE_NAME": "application.com.vuhnger.cight.123"
      ]))
    #expect(!LaunchAgent.isStartedByAgent(environment: [:]))
  }
}

struct LaunchAgentPlistTests {
  private func load() throws -> [String: Any] {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let url = root.appendingPathComponent("Resources/LaunchAgent/\(LaunchAgent.plistName)")
    let data = try Data(contentsOf: url)
    return try #require(
      try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
  }

  @Test func startsTheBundledExecutableAtLoad() throws {
    let plist = try load()
    #expect(plist["Label"] as? String == LaunchAgent.label)
    #expect(plist["BundleProgram"] as? String == "Contents/MacOS/Cight")
    #expect(plist["RunAtLoad"] as? Bool == true)
    #expect(plist["AssociatedBundleIdentifiers"] as? [String] == ["com.vuhnger.cight"])
  }

  @Test func restartsOnlyAfterANonZeroExit() throws {
    let keepAlive = try #require(try load()["KeepAlive"] as? [String: Any])
    #expect(keepAlive["SuccessfulExit"] as? Bool == false)
  }

  @Test func plistNameMatchesTheLabel() {
    #expect(LaunchAgent.plistName == "\(LaunchAgent.label).plist")
  }
}
