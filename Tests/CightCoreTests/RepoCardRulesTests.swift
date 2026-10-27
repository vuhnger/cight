import Foundation
import Testing

@testable import CightCore

struct RepoCardRulesTests {
  @Test func aRepoWithNothingActiveIsCollapsed() {
    #expect(!RepoCardRules.isExpanded(hasActiveRun: false, userChoice: nil, hasProblem: false))
  }

  @Test func anActiveRunExpandsTheCard() {
    #expect(RepoCardRules.isExpanded(hasActiveRun: true, userChoice: nil, hasProblem: false))
  }

  @Test func aManualToggleWinsOverTheActiveState() {
    #expect(!RepoCardRules.isExpanded(hasActiveRun: true, userChoice: false, hasProblem: false))
    #expect(RepoCardRules.isExpanded(hasActiveRun: false, userChoice: true, hasProblem: false))
  }

  @Test func aProblemRepoNeverExpands() {
    #expect(!RepoCardRules.isExpanded(hasActiveRun: true, userChoice: true, hasProblem: true))
  }

  @Test func theNewestRunComesFirst() {
    let order = RepoCardRules.newestFirst([
      (id: "old", newest: at(10)), (id: "new", newest: at(500)), (id: "mid", newest: at(100)),
    ])
    #expect(order == ["new", "mid", "old"])
  }

  @Test func reposWithoutRunsSinkAndTiesFollowTheName() {
    let order = RepoCardRules.newestFirst([
      (id: "none", newest: nil), (id: "b", newest: at(5)), (id: "a", newest: at(5)),
    ])
    #expect(order == ["a", "b", "none"])
  }
}
