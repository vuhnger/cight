import Foundation

public struct WatchedRepo: Codable, Sendable, Equatable {
  public let owner: String
  public let name: String
  public let defaultBranch: String
  public var filter: BranchFilter

  public init(owner: String, name: String, defaultBranch: String, filter: BranchFilter) {
    self.owner = owner
    self.name = name
    self.defaultBranch = defaultBranch
    self.filter = filter
  }

  func matches(owner: String, name: String) -> Bool {
    self.owner.lowercased() == owner.lowercased() && self.name.lowercased() == name.lowercased()
  }
}

public struct WatchList {
  public enum AddOutcome: Sendable, Equatable {
    case added
    case duplicate
    case full
  }

  public static let maxCount = 8
  static let key = "watchedRepos"

  public private(set) var repos: [WatchedRepo]
  private let defaults: UserDefaults

  public init(defaults: UserDefaults) {
    self.defaults = defaults
    let stored =
      defaults.data(forKey: Self.key)
      .flatMap { try? JSONDecoder().decode([WatchedRepo].self, from: $0) } ?? []
    var unique: [WatchedRepo] = []
    for repo in stored
    where !unique.contains(where: { $0.matches(owner: repo.owner, name: repo.name) }) {
      unique.append(repo)
    }
    repos = Array(unique.prefix(Self.maxCount))
  }

  @discardableResult
  public mutating func add(_ repo: WatchedRepo) -> AddOutcome {
    if repos.contains(where: { $0.matches(owner: repo.owner, name: repo.name) }) {
      return .duplicate
    }
    guard repos.count < Self.maxCount else { return .full }
    repos.append(repo)
    save()
    return .added
  }

  public mutating func remove(owner: String, name: String) {
    repos.removeAll { $0.matches(owner: owner, name: name) }
    save()
  }

  public mutating func setFilter(_ filter: BranchFilter, owner: String, name: String) {
    guard let index = repos.firstIndex(where: { $0.matches(owner: owner, name: name) }) else {
      return
    }
    repos[index].filter = filter
    save()
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(repos), forKey: Self.key)
  }
}
