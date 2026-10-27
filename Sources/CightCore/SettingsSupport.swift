import Foundation

public enum UserMessage {
  public static func text(for error: GitHubError, now: Date) -> String {
    switch error {
    case .unauthorized:
      "GitHub CLI not found or not signed in. Install gh and run gh auth login."
    case .rateLimited(let resumeAt):
      "GitHub rate limit reached. Try again in \(Formatting.duration(resumeAt.timeIntervalSince(now)))."
    case .notFound:
      "Repository not found. Check the spelling and that your account can see it."
    case .server(let status):
      "GitHub returned an error (\(status)). Try again shortly."
    case .transport:
      "Cannot reach GitHub. Check your connection."
    case .decoding:
      "GitHub sent a response Cight could not read."
    }
  }

  public static func text(for result: AddRepoResult, now: Date) -> String? {
    switch result {
    case .added: nil
    case .duplicate: "Already watched."
    case .full:
      "\(WatchList.maxCount) of \(WatchList.maxCount) repositories are watched. Remove one first."
    case .invalidInput: "Enter a repository as owner/repo or paste its GitHub URL."
    case .failed(let error): text(for: error, now: now)
    }
  }
}

public enum LaunchAgent {
  public static let label = "com.vuhnger.cight.agent"
  public static let plistName = "\(label).plist"

  public static let argument = "--launch-agent"

  public static func isStartedByAgent(arguments: [String]) -> Bool {
    arguments.dropFirst().contains(argument)
  }
}

public enum SettingsLaunchPolicy {
  public static func shouldOpen(startedByLaunchAgent: Bool, watchedCount: Int) -> Bool {
    !startedByLaunchAgent || watchedCount == 0
  }
}
