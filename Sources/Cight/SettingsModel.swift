import CightCore
import Foundation
import Observation

@MainActor
@Observable
final class SettingsModel {
  enum Pane: String, CaseIterable {
    case repositories = "Repositories"
    case general = "General"
  }

  var pane = Pane.repositories
  var query = ""
  private(set) var watched: [WatchedRepo]
  private(set) var allRepos: [Repo] = []
  private(set) var isLoading = false
  private(set) var isAdding = false
  private(set) var loadMessage: String?
  private(set) var addMessage: String?

  private let store: WatchStore
  private let client: GitHubClient

  init(store: WatchStore, client: GitHubClient) {
    self.store = store
    self.client = client
    watched = store.repos()
  }

  var results: [Repo] {
    RepoSearch.filter(allRepos, query: query, excluding: watched)
  }

  var typedRepo: (owner: String, name: String)? {
    guard let parsed = RepoInput.parse(query) else { return nil }
    let typed = "\(parsed.owner)/\(parsed.name)".lowercased()
    let known = allRepos.contains { $0.fullName.lowercased() == typed }
    let alreadyWatched = watched.contains { "\($0.owner)/\($0.name)".lowercased() == typed }
    return known || alreadyWatched ? nil : parsed
  }

  var countText: String {
    "\(watched.count) of \(WatchList.maxCount)"
  }

  func loadRepos() async {
    isLoading = true
    defer { isLoading = false }
    do {
      allRepos = try await client.repos()
      loadMessage = nil
    } catch let error as GitHubError {
      loadMessage = UserMessage.text(for: error, now: Date())
    } catch {
      return
    }
  }

  func add(_ repo: Repo) {
    finish(RepoAdder.add(repo: repo, store: { self.store.add($0) }))
  }

  func addTyped() async {
    isAdding = true
    defer { isAdding = false }
    let result = await RepoAdder.add(
      input: query, fetch: { try await self.client.repo(owner: $0, name: $1) },
      store: { self.store.add($0) })
    finish(result)
  }

  func remove(_ repo: WatchedRepo) {
    store.remove(repo.owner, repo.name)
    watched = store.repos()
    addMessage = nil
  }

  func setFilter(_ filter: BranchFilter, for repo: WatchedRepo) {
    store.setFilter(filter, repo.owner, repo.name)
    watched = store.repos()
  }

  private func finish(_ result: AddRepoResult) {
    addMessage = UserMessage.text(for: result, now: Date())
    watched = store.repos()
    if case .added = result { query = "" }
  }
}
