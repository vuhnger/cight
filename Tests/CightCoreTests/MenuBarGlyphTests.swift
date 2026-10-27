import Foundation
import Testing

@testable import CightCore

private func running(id: Int, started: TimeInterval = 0, workflow: Int = 1) -> WorkflowRun {
  makeRun(
    id: id, workflow: workflow, status: "in_progress", conclusion: nil, created: started,
    started: started)
}

private func history(workflow: Int = 1) -> [WorkflowRun] {
  (1...3).map {
    successfulRun(id: 100 + $0, workflow: workflow, created: Double($0 * -1000), duration: 60)
  }
}

private func repo(_ visible: [WorkflowRun], history: [WorkflowRun] = []) -> MenuBarRepo {
  MenuBarRepo(visible: visible, history: history)
}

struct MenuBarGlyphTests {
  @Test func failedBeatsEveryOtherState() {
    let runs = [
      running(id: 1), makeRun(id: 2, workflow: 2, conclusion: "failure"),
      makeRun(id: 3, workflow: 3),
    ]
    #expect(MenuBarGlyphs.glyph(for: repo(runs), now: at(10)) == .failed)
  }

  @Test func passedQueuedAndRunningMapToTheirOwnGlyph() {
    let queued = makeRun(id: 1, status: "queued", conclusion: nil)
    #expect(MenuBarGlyphs.glyph(for: repo([queued]), now: at(10)) == .queued)
    #expect(MenuBarGlyphs.glyph(for: repo([makeRun(id: 2)]), now: at(10)) == .passed)
    #expect(
      MenuBarGlyphs.glyph(for: repo([running(id: 3), queued]), now: at(10))
        == .running(progress: nil))
  }

  @Test func runningProgressFollowsTheMedianOfPastRuns() {
    let glyph = MenuBarGlyphs.glyph(
      for: repo([running(id: 1)], history: history()), now: at(30))
    #expect(glyph == .running(progress: 0.5))
  }

  @Test func progressSnapsToTwelfthsSoTheIconRedrawsRarely() {
    let a = MenuBarGlyphs.glyph(for: repo([running(id: 1)], history: history()), now: at(31))
    let b = MenuBarGlyphs.glyph(for: repo([running(id: 1)], history: history()), now: at(32))
    #expect(a == b)
  }

  @Test func runningPastTheMedianIsOverdue() {
    let glyph = MenuBarGlyphs.glyph(
      for: repo([running(id: 1)], history: history()), now: at(90))
    #expect(glyph == .overdue)
  }

  @Test func anOverdueRunWinsOverAFresherRunningOne() {
    let runs = [running(id: 1, started: 0, workflow: 1), running(id: 2, started: 80, workflow: 2)]
    let past = history(workflow: 1) + history(workflow: 2)
    #expect(MenuBarGlyphs.glyph(for: repo(runs, history: past), now: at(90)) == .overdue)
  }

  @Test func neutralOnlyAndEmptyReposShowNothing() {
    let skipped = makeRun(id: 1, conclusion: "skipped")
    #expect(MenuBarGlyphs.glyph(for: repo([skipped]), now: at(10)) == nil)
    #expect(MenuBarGlyphs.glyph(for: repo([]), now: at(10)) == nil)
  }

  @Test func glyphsKeepPanelOrderAndDropPassedAndEmptyRepos() {
    let repos = [
      repo([makeRun(id: 1, conclusion: "failure")]), repo([makeRun(id: 2)]), repo([]),
      repo([makeRun(id: 3, conclusion: "skipped")]),
      repo([makeRun(id: 4, status: "queued", conclusion: nil)]),
    ]
    #expect(
      MenuBarGlyphs.glyphs(repos: repos, signedOut: false, now: at(10)) == [.failed, .queued])
  }

  @Test func allPassedShowsTheIdleIcon() {
    let repos = [repo([makeRun(id: 1)]), repo([makeRun(id: 2)])]
    #expect(MenuBarGlyphs.glyphs(repos: repos, signedOut: false, now: at(10)) == [.idle])
  }

  @Test func nothingWatchedShowsTheIdleIcon() {
    #expect(MenuBarGlyphs.glyphs(repos: [], signedOut: false, now: at(10)) == [.idle])
    #expect(MenuBarGlyphs.glyphs(repos: [repo([])], signedOut: false, now: at(10)) == [.idle])
  }

  @Test func mixedActiveAndPassedShowsOnlyTheActiveOnes() {
    let repos = [repo([makeRun(id: 1)]), repo([running(id: 2)]), repo([makeRun(id: 3)])]
    #expect(
      MenuBarGlyphs.glyphs(repos: repos, signedOut: false, now: at(10))
        == [.running(progress: nil)])
  }

  @Test func signedOutIsASingleLockWhateverTheRepos() {
    let repos = [repo([makeRun(id: 1, conclusion: "failure")]), repo([makeRun(id: 2)])]
    #expect(MenuBarGlyphs.glyphs(repos: repos, signedOut: true, now: at(10)) == [.signedOut])
    #expect(MenuBarGlyphs.glyphs(repos: [], signedOut: true, now: at(10)) == [.signedOut])
  }
}
