import Foundation

public enum RepoCardRules {
  public static func isExpanded(hasActiveRun: Bool, userChoice: Bool?, hasProblem: Bool) -> Bool {
    guard !hasProblem else { return false }
    return userChoice ?? hasActiveRun
  }

  public static func newestFirst(_ entries: [(id: String, newest: Date?)]) -> [String] {
    entries
      .sorted {
        let lhs = $0.newest ?? .distantPast
        let rhs = $1.newest ?? .distantPast
        return (rhs, $0.id) < (lhs, $1.id)
      }
      .map(\.id)
  }
}
