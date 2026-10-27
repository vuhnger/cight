import Foundation

public struct Discovery: Sendable, Equatable {
  public let repos: [Repo]
  public let error: GitHubError?
}

public enum RepoDiscovery {
  public static let window: TimeInterval = 7 * 24 * 60 * 60
  public static let cap = 8

  public static func discover(
    previous: [Repo],
    now: Date,
    candidates: @Sendable () async throws -> [Repo],
    latestRun: @escaping @Sendable (Repo) async throws -> WorkflowRun?
  ) async -> Discovery {
    let cutoff = now.addingTimeInterval(-window)
    do {
      let pushed = try await candidates().filter { ($0.pushedAt ?? .distantPast) >= cutoff }
      let found = try await withThrowingTaskGroup(of: (Repo, Date)?.self) { group in
        for repo in pushed {
          group.addTask {
            do {
              guard let run = try await latestRun(repo), run.createdAt >= cutoff else {
                return nil
              }
              return (repo, run.createdAt)
            } catch GitHubError.notFound {
              return nil
            } catch GitHubError.server(403) {
              return nil
            }
          }
        }
        var all: [(Repo, Date)] = []
        for try await item in group {
          if let item { all.append(item) }
        }
        return all
      }
      let ordered = found.sorted { ($1.1, $0.0.fullName) < ($0.1, $1.0.fullName) }
      return Discovery(repos: ordered.prefix(cap).map(\.0), error: nil)
    } catch {
      return Discovery(repos: previous, error: error as? GitHubError ?? .transport(.unknown))
    }
  }
}
