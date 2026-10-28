import Foundation
import Testing

@testable import CightCore

private func run(url: String?, pull: Int? = nil, mergeRequest: Bool = false) -> WorkflowRun {
  WorkflowRun(
    id: 1, workflowId: 1, createdAt: t0, name: nil, displayTitle: nil, status: "completed",
    conclusion: "success", event: "push", headBranch: "main",
    pullRequests: pull.map { [PullRequestRef(number: $0)] }, runStartedAt: nil, updatedAt: nil,
    htmlUrl: url, actor: nil, headRepository: nil, isMergeRequest: mergeRequest)
}

struct RunLinkTests {
  @Test func aGitHubRunWithAPullRequestLinksToThePullRequest() {
    let github = run(url: "https://github.com/o/r/actions/runs/9", pull: 7)
    #expect(
      github.targetLink(host: "github.com")?.absoluteString == "https://github.com/o/r/pull/7")
  }

  @Test func aGitLabMergeRequestPipelineLinksToTheMergeRequest() {
    let gitlab = run(url: "https://gitlab.com/g/sub/p/-/pipelines/9", pull: 12, mergeRequest: true)
    #expect(
      gitlab.targetLink(host: "gitlab.com")?.absoluteString
        == "https://gitlab.com/g/sub/p/-/merge_requests/12")
  }

  @Test func aRunWithoutAPullRequestLinksToTheRun() {
    let plain = run(url: "https://github.com/o/r/actions/runs/9")
    #expect(
      plain.targetLink(host: "github.com")?.absoluteString
        == "https://github.com/o/r/actions/runs/9")
  }

  @Test(arguments: [
    "http://github.com/o/r/actions/runs/9", "https://evil.example/o/r/actions/runs/9",
  ])
  func aLinkThatIsNotHTTPSOnTheProviderHostIsRejected(link: String) {
    #expect(run(url: link, pull: 7).targetLink(host: "github.com") == nil)
  }
}
