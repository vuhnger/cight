import Foundation
import Testing

@testable import CightCore

private func repo(_ fullName: String, id: Int = 1, host: String = Repo.githubHost) -> Repo {
  Repo(
    id: id, name: String(fullName.split(separator: "/").last ?? ""), fullName: fullName,
    defaultBranch: "main", pushedAt: t0, host: host)
}

struct ProviderIdentityTests {
  @Test func theSameFullNameOnThreeHostsGivesThreeKeys() {
    let keys = [
      repo("foo/bar").key, repo("foo/bar", host: "gitlab.com").key,
      repo("foo/bar", host: "gitlab.example.com").key,
    ]
    #expect(Set(keys).count == 3)
  }

  @Test func aGitHubKeyStaysTheLowercasedFullNameSoSavedStateKeepsWorking() {
    #expect(repo("Foo/Bar").key == "foo/bar")
  }

  @Test func decodedGitHubReposDefaultToTheGitHubHost() throws {
    let repos = try JSONDecoder.github.decode([Repo].self, from: Fixture.data("repos"))
    #expect(repos.allSatisfy { $0.host == Repo.githubHost })
  }

  @Test func equalRepoAndRunIdsOnDifferentHostsDoNotShareTrackerState() {
    var github = RunTracker()
    var gitlab = RunTracker()
    _ = github.ingest(repo: repo("foo/bar").key, runs: [makeRun(id: 5, conclusion: "success")])
    _ = gitlab.ingest(
      repo: repo("foo/bar", host: "gitlab.com").key, runs: [makeRun(id: 5, conclusion: "success")])
    let failedOnGitHub = github.ingest(
      repo: repo("foo/bar").key, runs: [makeRun(id: 6, conclusion: "failure", created: 10)])
    #expect(failedOnGitHub.map(\.kind) == [.failed])
    #expect(failedOnGitHub.first?.repo == "foo/bar")
    let failedOnGitLab = gitlab.ingest(
      repo: "gitlab.com/foo/bar", runs: [makeRun(id: 6, conclusion: "failure", created: 10)])
    #expect(failedOnGitLab.first?.repo == "gitlab.com/foo/bar")
  }

  @Test func theSharedCapKeepsTheNewestEightAcrossProviders() {
    let github = Discovery(
      repos: (1...6).map { repo("o/gh\($0)", id: $0) }, error: nil,
      newest: Dictionary(
        uniqueKeysWithValues: (1...6).map { (repo("o/gh\($0)").key, at(TimeInterval(-$0 * 100))) }))
    let gitlab = Discovery(
      repos: (1...6).map { repo("g/gl\($0)", id: $0, host: "gitlab.com") }, error: nil,
      newest: Dictionary(
        uniqueKeysWithValues: (1...6).map {
          (repo("g/gl\($0)", host: "gitlab.com").key, at(TimeInterval(-$0 * 100 - 50)))
        }))
    let merged = RepoDiscovery.merge([github, gitlab])
    #expect(merged.count == RepoDiscovery.cap)
    #expect(
      merged.map(\.fullName)
        == ["o/gh1", "g/gl1", "o/gh2", "g/gl2", "o/gh3", "g/gl3", "o/gh4", "g/gl4"])
  }

  @Test func theCapKeepsTwoReposThatShareAnIdAcrossHosts() {
    let merged = RepoDiscovery.merge([
      Discovery(repos: [repo("foo/bar", id: 7)], error: nil, newest: ["foo/bar": at(0)]),
      Discovery(
        repos: [repo("foo/bar", id: 7, host: "gitlab.com")], error: nil,
        newest: ["gitlab.com/foo/bar": at(-1)]),
    ])
    #expect(merged.map(\.host) == [Repo.githubHost, "gitlab.com"])
  }

  @Test func discoveryKeepsTheRunDateOfEachKeptRepo() async {
    let result = await RepoDiscovery.discover(
      previous: [], now: at(0), candidates: { [repo("o/a")] },
      latestRun: { _ in makeRun(id: 1, created: -60) })
    #expect(result.newest == ["o/a": at(-60)])
  }

  @Test func readsEveryHostFromTheGlabConfig() {
    let yaml = """
      git_protocol: ssh
      hosts:
          gitlab.com:
              token: secret
              api_host: gitlab.com
          "gitlab.example.com:8443":
              use_keyring: true
      editor:
      """
    #expect(GlabCLI.parseHosts(yaml) == ["gitlab.com", "gitlab.example.com:8443"])
  }

  @Test func aConfigWithoutHostsYieldsNone() {
    #expect(GlabCLI.parseHosts("git_protocol: ssh\n").isEmpty)
    #expect(GlabCLI.parseHosts("").isEmpty)
  }

  @Test func rejectsHostsThatCouldRedirectARequest() {
    #expect(GlabCLI.parseHosts("hosts:\n  evil.com/path:\n    token: x\n  a b:\n").isEmpty)
  }

  @Test func withoutGlabThereAreNoHostsAndNoToken() async {
    #expect(GlabCLI.hosts(paths: ["/nonexistent/glab"]).isEmpty)
    let token = await GlabCLI.token(host: "gitlab.com", paths: ["/nonexistent/glab"])
    #expect(token == nil)
  }

  @Test func aGitLabSignOutUsesItsOwnGate() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    var github = SignOutGate(defaults: defaults)
    var gitlab = SignOutGate(defaults: defaults, key: SignOutGate.gitLabKey)
    _ = github.shouldNotify(.signedOut)
    let githubNotified = github.shouldNotify(.signedOut)
    github.didPost()
    let gitlabFirst = gitlab.shouldNotify(.signedOut)
    let gitlabSecond = gitlab.shouldNotify(.signedOut)
    let githubAgain = github.shouldNotify(.signedOut)
    #expect(githubNotified)
    #expect(!gitlabFirst)
    #expect(gitlabSecond)
    #expect(!githubAgain)
  }

  @Test func theGitLabToastUsesTheAgreedCopy() {
    #expect(ToastContent.gitLabSignedOut.line1 == "Signed out of GitLab")
    #expect(
      ToastContent.gitLabSignedOut.line2 == "Run glab auth login in Terminal to resume monitoring.")
    #expect(ToastContent.gitLabSignedOut.glyph == .signedOut)
  }

  @Test func aToastForAMergeRequestRunSaysSo() {
    let run = GitLabMapping.run(
      GitLabPipeline(
        id: 1, projectId: 2, ref: "refs/merge-requests/12/head", status: "failed",
        source: "merge_request_event", createdAt: t0, updatedAt: t0, webUrl: nil, name: nil),
      project: repo("g/p", host: "gitlab.com"), actor: nil, mergeRequest: nil)
    let toast = ToastContent.make(
      for: RunEvent(kind: .failed, repo: "gitlab.com/g/p", run: run), settings: .init())
    #expect(toast?.pullRequest == 12)
    #expect(toast?.isMergeRequest == true)
    #expect(toast?.line2 == "Pipeline failed on !12")
  }

  @Test func aGitLabSignOutShowsWhenGitHubHasNothingToSayButNeverReplacesAGitHubProblem() {
    #expect(NoticePolicy.combined(github: nil, gitLabSignedOut: true) == .gitLabSignedOut)
    #expect(NoticePolicy.combined(github: .noRecentRuns, gitLabSignedOut: true) == .gitLabSignedOut)
    #expect(NoticePolicy.combined(github: .signedOut, gitLabSignedOut: true) == .signedOut)
    #expect(NoticePolicy.combined(github: nil, gitLabSignedOut: false) == nil)
  }
}
