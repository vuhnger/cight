import Foundation
import Testing

@testable import PeekCore

private let now = at(0)
private let day: TimeInterval = 86_400

private func repo(_ name: String, pushed: TimeInterval = -3_600) -> Repo {
  Repo(
    id: abs(name.hashValue), name: name, fullName: "o/\(name)", defaultBranch: "main",
    pushedAt: at(pushed))
}

private func discover(
  previous: [Repo] = [],
  candidates: [Repo],
  runs: [String: TimeInterval],
  failing: [String: GitHubError] = [:]
) async -> Discovery {
  await RepoDiscovery.discover(
    previous: previous, now: now, candidates: { candidates },
    latestRun: { repo in
      if let error = failing[repo.name] { throw error }
      return runs[repo.name].map { makeRun(id: 1, created: $0) }
    })
}

private actor Probed {
  private(set) var names: [String] = []
  func add(_ name: String) { names.append(name) }
}

struct RepoDiscoveryTests {
  @Test func aRepoPushedExactlySevenDaysAgoIsACandidateAndOneSecondOlderIsNot() async {
    let result = await discover(
      candidates: [repo("edge", pushed: -7 * day), repo("old", pushed: -7 * day - 1)],
      runs: ["edge": -3_600, "old": -3_600])
    #expect(result.repos.map(\.name) == ["edge"])
  }

  @Test func aRunOlderThanSevenDaysDoesNotCount() async {
    let result = await discover(
      candidates: [repo("a"), repo("b")], runs: ["a": -7 * day, "b": -7 * day - 1])
    #expect(result.repos.map(\.name) == ["a"])
  }

  @Test func neverProbesReposOutsideTheWindow() async {
    let probed = Probed()
    _ = await RepoDiscovery.discover(
      previous: [], now: now,
      candidates: { [repo("old", pushed: -8 * day), repo("new")] },
      latestRun: { repo in
        await probed.add(repo.name)
        return nil
      })
    #expect(await probed.names == ["new"])
  }

  @Test func keepsTheEightNewestRuns() async {
    let names = (0..<10).map { "r\($0)" }
    let result = await discover(
      candidates: names.map { repo($0) },
      runs: Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, -Double($0) * 60) }))
    #expect(result.repos.map(\.name) == (0..<8).map { "r\($0)" })
    #expect(result.error == nil)
  }

  @Test func ordersByNewestRunNotByPushDate() async {
    let result = await discover(
      candidates: [repo("pushedLast", pushed: -60), repo("ranLast", pushed: -600)],
      runs: ["pushedLast": -5_000, "ranLast": -100])
    #expect(result.repos.map(\.name) == ["ranLast", "pushedLast"])
  }

  @Test func skipsReposWithoutRunsOrWithActionsOffOrGone() async {
    let result = await discover(
      candidates: [repo("none"), repo("gone"), repo("off"), repo("ok")],
      runs: ["ok": -60],
      failing: ["gone": .notFound, "off": .server(403)])
    #expect(result.repos.map(\.name) == ["ok"])
    #expect(result.error == nil)
  }

  @Test func aSuccessfulDiscoveryWithNothingReplacesThePreviousList() async {
    let result = await discover(previous: [repo("stale")], candidates: [repo("a")], runs: [:])
    #expect(result.repos.isEmpty)
    #expect(result.error == nil)
  }

  @Test func aFailedCandidateListKeepsThePreviousList() async {
    let previous = [repo("kept")]
    let result = await RepoDiscovery.discover(
      previous: previous, now: now, candidates: { throw GitHubError.transport(.timedOut) },
      latestRun: { _ in nil })
    #expect(result == Discovery(repos: previous, error: .transport(.timedOut)))
  }

  @Test(arguments: [
    GitHubError.transport(.notConnectedToInternet), .rateLimited(resumeAt: at(60)), .unauthorized,
    .server(502),
  ])
  func aFailedProbeKeepsThePreviousListInsteadOfShowingPartialResults(error: GitHubError) async {
    let previous = [repo("kept")]
    let result = await discover(
      previous: previous, candidates: [repo("a"), repo("b")], runs: ["a": -60],
      failing: ["b": error])
    #expect(result == Discovery(repos: previous, error: error))
  }
}
