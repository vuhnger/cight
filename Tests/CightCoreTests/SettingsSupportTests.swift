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
