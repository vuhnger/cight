import Foundation

public enum GhTokenReader {
  public static let defaultPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

  public static func isInstalled(paths: [String] = defaultPaths) -> Bool {
    paths.contains(where: FileManager.default.isExecutableFile)
  }

  public static func read(
    paths: [String] = defaultPaths, timeout: TimeInterval = 5
  ) async -> String? {
    await CLIRunner.read(
      paths: paths, arguments: ["auth", "token", "--hostname", Repo.githubHost], timeout: timeout)
  }
}
