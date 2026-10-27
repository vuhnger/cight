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

  private let monitor: Monitor
  private var session = SessionState.unknown

  private var client: GitHubClient { monitor.client }

  init(monitor: Monitor) {
    self.monitor = monitor
    watched = monitor.watched
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
    } catch is CancellationError {
      return
    } catch let error as GitHubError {
      if case .transport(.cancelled) = error { return }
      loadMessage = UserMessage.text(for: error, now: Date())
    } catch {
      loadMessage = "Could not load your repositories. Try again shortly."
    }
  }

  func sessionChanged(_ next: SessionState) async {
    let previous = session
    session = next
    if next == .signedIn, previous == .signedOut {
      await loadRepos()
    }
  }

  func add(_ repo: Repo) {
    finish(RepoAdder.add(repo: repo, store: { self.monitor.add($0) }), submitted: query)
  }

  func addTyped() async {
    isAdding = true
    defer { isAdding = false }
    let submitted = query
    let result = await RepoAdder.add(
      input: query, fetch: { try await self.client.repo(owner: $0, name: $1) },
      store: { self.monitor.add($0) })
    finish(result, submitted: submitted)
  }

  func remove(_ repo: WatchedRepo) {
    monitor.remove(owner: repo.owner, name: repo.name)
    watched = monitor.watched
    addMessage = nil
  }

  func setFilter(_ filter: BranchFilter, for repo: WatchedRepo) {
    monitor.setFilter(filter, owner: repo.owner, name: repo.name)
    watched = monitor.watched
  }

  private func finish(_ result: AddRepoResult, submitted: String) {
    addMessage = UserMessage.text(for: result, now: Date())
    watched = monitor.watched
    if case .added = result, query == submitted { query = "" }
  }
}
