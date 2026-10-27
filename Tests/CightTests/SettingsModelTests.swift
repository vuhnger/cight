import Foundation
import Testing

@testable import Cight
@testable import CightCore

@MainActor
@Suite(.serialized)
struct SettingsModelTests {
  private func makeModel(
    _ handler: @escaping @Sendable (URLRequest) async -> Reply
  ) -> SettingsModel {
    Stub.install(handler)
    return SettingsModel(monitor: Monitor(defaults: freshDefaults(), client: stubbedClient()))
  }

  @Test func loadsTheUsersRepositories() async {
    let model = makeModel { _ in Reply(body: reposJSON) }
    await model.loadRepos()
    #expect(model.allRepos.map(\.fullName) == ["o/alpha", "o/beta"])
    #expect(model.loadMessage == nil)
    #expect(!model.isLoading)
  }

  @Test func aServerErrorIsShownAsAMessage() async {
    let model = makeModel { _ in Reply(status: 500) }
    await model.loadRepos()
    #expect(model.loadMessage?.contains("500") == true)
  }

  @Test func anUnreadableResponseIsShownAsAMessage() async {
    let model = makeModel { _ in Reply(body: "not json") }
    await model.loadRepos()
    #expect(model.loadMessage != nil)
  }

  @Test func aCancelledLoadStaysSilentAndClearsTheSpinner() async {
    let model = makeModel { _ in Reply(error: URLError(.cancelled)) }
    await model.loadRepos()
    #expect(model.loadMessage == nil)
    #expect(!model.isLoading)
  }

  @Test func aCancelledTaskDoesNotReportAnError() async {
    let model = makeModel { _ in
      try? await Task.sleep(for: .seconds(5))
      return Reply(body: reposJSON)
    }
    let task = Task { await model.loadRepos() }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    await task.value
    #expect(model.loadMessage == nil)
    #expect(!model.isLoading)
  }

  @Test func signingInAgainReloadsTheRepositories() async {
    let model = makeModel { _ in Reply(status: 401) }
    await model.loadRepos()
    #expect(model.loadMessage != nil)
    await model.sessionChanged(.signedOut)
    Stub.install { _ in Reply(body: reposJSON) }
    await model.sessionChanged(.signedIn)
    #expect(model.allRepos.count == 2)
    #expect(model.loadMessage == nil)
  }

  @Test func anOfflineSampleBetweenDoesNotHideTheSignIn() async {
    let model = makeModel { _ in Reply(status: 401) }
    await model.loadRepos()
    await model.sessionChanged(.signedOut)
    await model.sessionChanged(.unknown)
    Stub.install { _ in Reply(body: reposJSON) }
    await model.sessionChanged(.signedIn)
    #expect(model.allRepos.count == 2)
  }

  @Test func theFirstSuccessfulPollDoesNotTriggerASecondLoad() async {
    let model = makeModel { _ in Reply(body: reposJSON) }
    await model.loadRepos()
    let before = Stub.requestedPaths.count
    await model.sessionChanged(.signedIn)
    #expect(Stub.requestedPaths.count == before)
  }

  @Test func aQueryTypedWhileAddingSurvivesTheAdd() async {
    let model = makeModel { request in
      try? await Task.sleep(for: .milliseconds(300))
      return Reply(
        body: """
          {"archived":false,"default_branch":"main","full_name":"o/gamma","id":3,\
          "name":"gamma","owner":{"id":9,"login":"o"},"private":false,\
          "pushed_at":"2026-10-27T18:21:25Z"}
          """)
    }
    model.query = "o/gamma"
    let adding = Task { await model.addTyped() }
    try? await Task.sleep(for: .milliseconds(100))
    model.query = "something else"
    await adding.value
    #expect(model.watched.map(\.name) == ["gamma"])
    #expect(model.query == "something else")
  }

  @Test func theQueryClearsAfterAnUntouchedAdd() async {
    let model = makeModel { _ in
      Reply(
        body: """
          {"archived":false,"default_branch":"main","full_name":"o/gamma","id":3,\
          "name":"gamma","owner":{"id":9,"login":"o"},"private":false,\
          "pushed_at":"2026-10-27T18:21:25Z"}
          """)
    }
    model.query = "o/gamma"
    await model.addTyped()
    #expect(model.query.isEmpty)
    #expect(model.countText == "1 of 8")
  }

  @Test func removingAndChangingFiltersUpdatesTheWatchedList() async throws {
    let model = makeModel { _ in Reply(body: reposJSON) }
    await model.loadRepos()
    model.add(model.allRepos[0])
    let repo = try #require(model.watched.first)
    #expect(repo.filter == .mine)
    model.setFilter(.all, for: repo)
    #expect(model.watched.first?.filter == .all)
    model.remove(repo)
    #expect(model.watched.isEmpty)
  }
}
