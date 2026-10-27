import Foundation
import Testing

@testable import CightCore

private func repo(_ fullName: String, id: Int = 1, branch: String = "main") -> Repo {
  let json =
    #"{"id": \#(id), "name": "x", "full_name": "\#(fullName)", "default_branch": "\#(branch)"}"#
  return try! JSONDecoder.github.decode(Repo.self, from: Data(json.utf8))
}

struct RepoInputTests {
  @Test(
    arguments: [
      ("swiftlang/swift-format", "swiftlang", "swift-format"),
      ("  swiftlang/swift-format\n", "swiftlang", "swift-format"),
      ("https://github.com/swiftlang/swift-format", "swiftlang", "swift-format"),
      ("http://github.com/swiftlang/swift-format/", "swiftlang", "swift-format"),
      ("github.com/swiftlang/swift-format.git", "swiftlang", "swift-format"),
      ("git@github.com:swiftlang/swift-format.git", "swiftlang", "swift-format"),
      ("https://github.com/swiftlang/swift-format/actions/runs/1", "swiftlang", "swift-format"),
      ("Some-Org_1/a.b_c-2", "Some-Org_1", "a.b_c-2"),
    ] as [(String, String, String)])
  func parsesOwnerAndName(text: String, owner: String, name: String) {
    let parsed = RepoInput.parse(text)
    #expect(parsed?.owner == owner)
    #expect(parsed?.name == name)
  }

  @Test(
    arguments: [
      "", "   ", "swift-format", "a/b/c", "a b/c", "a/b c", "a/b?x=1", "/b", "a/", "../x",
      "a/..", "github.com/a", "https://example.com/a/b", "a//b", "https://github.com/a",
    ])
  func rejectsAnythingThatIsNotOwnerSlashName(text: String) {
    #expect(RepoInput.parse(text) == nil)
  }

  @Test func searchMatchesAnyPartOfTheFullNameIgnoringCase() {
    let repos = [
      repo("vuhnger/cight"), repo("swiftlang/swift-format"), repo("octocat/Hello-World"),
    ]
    #expect(
      RepoSearch.filter(repos, query: "SWIFT", excluding: []).map(\.fullName) == [
        "swiftlang/swift-format"
      ])
    #expect(RepoSearch.filter(repos, query: "hello-w", excluding: []).count == 1)
    #expect(RepoSearch.filter(repos, query: "vuh", excluding: []).count == 1)
    #expect(RepoSearch.filter(repos, query: "zzz", excluding: []).isEmpty)
  }

  @Test func searchKeepsTheOrderAndReturnsEverythingForABlankQuery() {
    let repos = [repo("b/two"), repo("a/one"), repo("c/three")]
    #expect(
      RepoSearch.filter(repos, query: "  ", excluding: []).map(\.fullName) == [
        "b/two", "a/one", "c/three",
      ])
  }

  @Test func searchHidesRepositoriesAlreadyWatchedIgnoringCase() {
    let repos = [repo("Vuhnger/Cight"), repo("swiftlang/swift-format")]
    let watched = [
      WatchedRepo(owner: "vuhnger", name: "cight", defaultBranch: "main", filter: .mine)
    ]
    #expect(
      RepoSearch.filter(repos, query: "", excluding: watched).map(\.fullName) == [
        "swiftlang/swift-format"
      ])
  }

  @Test func buildsAWatchedRepoFromAFetchedRepo() throws {
    let watched = try #require(
      WatchedRepo(repo: repo("swiftlang/swift-format", branch: "trunk"), filter: .all))
    #expect(watched.owner == "swiftlang")
    #expect(watched.name == "swift-format")
    #expect(watched.defaultBranch == "trunk")
    #expect(watched.filter == .all)
  }

  @Test func refusesAFetchedRepoWithoutOwnerAndName() {
    #expect(WatchedRepo(repo: repo("no-slash"), filter: .all) == nil)
  }
}

struct RepoAdderTests {
  private func fetching(_ fullName: String) -> (String, String) async throws -> Repo {
    { _, _ in repo(fullName, branch: "trunk") }
  }

  @Test func validatesTypedInputWithTheServerThenAdds() async {
    var stored: [WatchedRepo] = []
    let result = await RepoAdder.add(
      input: " https://github.com/swiftlang/swift-format ",
      fetch: { owner, name in
        #expect(owner == "swiftlang")
        #expect(name == "swift-format")
        return repo("swiftlang/swift-format", branch: "trunk")
      },
      store: {
        stored.append($0)
        return .added
      })
    #expect(result == .added(stored[0]))
    #expect(stored[0].defaultBranch == "trunk")
    #expect(stored[0].filter == .mine)
  }

  @Test func rejectsBadInputWithoutAskingTheServer() async {
    let result = await RepoAdder.add(
      input: "not a repo",
      fetch: { _, _ in
        Issue.record("fetch must not run")
        return repo("a/b")
      },
      store: { _ in .added })
    #expect(result == .invalidInput)
  }

  @Test func passesServerErrorsThrough() async {
    let result = await RepoAdder.add(
      input: "a/b", fetch: { _, _ in throw GitHubError.notFound }, store: { _ in .added })
    #expect(result == .failed(.notFound))
  }

  @Test func reportsDuplicatesAndAFullList() async {
    let duplicate = await RepoAdder.add(
      input: "a/b", fetch: fetching("a/b"), store: { _ in .duplicate })
    let full = await RepoAdder.add(input: "a/b", fetch: fetching("a/b"), store: { _ in .full })
    #expect(duplicate == .duplicate)
    #expect(full == .full)
  }

  @Test func addsAPickedRepositoryWithoutANetworkCall() {
    var stored: [WatchedRepo] = []
    let result = RepoAdder.add(
      repo: repo("vuhnger/cight"),
      store: {
        stored.append($0)
        return .added
      })
    #expect(result == .added(stored[0]))
    #expect(stored[0].owner == "vuhnger")
  }
}
