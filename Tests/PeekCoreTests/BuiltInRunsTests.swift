import Foundation
import Testing

@testable import PeekCore

struct BuiltInRunsTests {
  @Test func dynamicRunIsDroppedWhenHidden() {
    let runs = [makeRun(id: 1, event: "dynamic"), makeRun(id: 2, event: "push")]
    #expect(BuiltInRuns.filter(runs, shown: false).map(\.id) == [2])
  }

  @Test func dynamicRunIsKeptWhenShown() {
    let runs = [makeRun(id: 1, event: "dynamic"), makeRun(id: 2, event: "push")]
    #expect(BuiltInRuns.filter(runs, shown: true).map(\.id) == [1, 2])
  }

  @Test func nonDynamicRunIsNeverBuiltIn() {
    #expect(!makeRun(id: 1, event: "pull_request").isBuiltIn)
    #expect(makeRun(id: 2, event: "dynamic").isBuiltIn)
  }

  @Test func defaultsToHiddenWhenNothingIsStored() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    #expect(!BuiltInRuns.isShown(in: defaults))
    defaults.set(true, forKey: BuiltInRuns.key)
    #expect(BuiltInRuns.isShown(in: defaults))
  }
}
