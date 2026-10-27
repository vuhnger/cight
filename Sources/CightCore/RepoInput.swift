import Foundation

public enum RepoPath {
  private static let segmentCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

  static func isValidSegment(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".."
      && value.unicodeScalars.allSatisfy(segmentCharacters.contains)
  }
}

public enum RepoInput {
  private static let urlPrefixes = [
    "https://github.com/", "http://github.com/", "git@github.com:", "github.com/",
  ]

  public static func parse(_ text: String) -> (owner: String, name: String)? {
    var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var isURL = false
    if let prefix = urlPrefixes.first(where: { rest.lowercased().hasPrefix($0) }) {
      rest = String(rest.dropFirst(prefix.count))
      isURL = true
    }
    var parts = rest.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    if parts.last?.isEmpty == true { parts.removeLast() }
    guard parts.count == 2 || (isURL && parts.count > 2) else { return nil }
    let owner = parts[0]
    var name = parts[1]
    if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
    guard RepoPath.isValidSegment(owner), RepoPath.isValidSegment(name) else { return nil }
    return (owner, name)
  }
}

public enum RepoSearch {
  public static func filter(
    _ repos: [Repo], query: String, excluding watched: [WatchedRepo]
  ) -> [Repo] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return repos.filter { repo in
      let name = repo.fullName.lowercased()
      return (needle.isEmpty || name.contains(needle))
        && !watched.contains { "\($0.owner)/\($0.name)".lowercased() == name }
    }
  }
}

extension WatchedRepo {
  public init?(repo: Repo, filter: BranchFilter) {
    let parts = repo.fullName.split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    self.init(
      owner: String(parts[0]), name: String(parts[1]), defaultBranch: repo.defaultBranch,
      filter: filter)
  }
}

public enum AddRepoResult: Sendable, Equatable {
  case added(WatchedRepo)
  case duplicate
  case full
  case invalidInput
  case failed(GitHubError)
}

public enum RepoAdder {
  public static func add(
    input: String,
    filter: BranchFilter = .mine,
    fetch: (String, String) async throws -> Repo,
    store: (WatchedRepo) -> WatchList.AddOutcome
  ) async -> AddRepoResult {
    guard let parsed = RepoInput.parse(input) else { return .invalidInput }
    do {
      let repo = try await fetch(parsed.owner, parsed.name)
      return add(repo: repo, filter: filter, store: store)
    } catch let error as GitHubError {
      return .failed(error)
    } catch {
      return .failed(.transport(.unknown))
    }
  }

  public static func add(
    repo: Repo,
    filter: BranchFilter = .mine,
    store: (WatchedRepo) -> WatchList.AddOutcome
  ) -> AddRepoResult {
    guard let watched = WatchedRepo(repo: repo, filter: filter) else { return .invalidInput }
    switch store(watched) {
    case .added: return .added(watched)
    case .duplicate: return .duplicate
    case .full: return .full
    }
  }
}
