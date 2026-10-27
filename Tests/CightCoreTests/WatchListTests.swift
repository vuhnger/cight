import Foundation
import Testing

@testable import CightCore

private func makeDefaults() -> UserDefaults {
  let defaults = UserDefaults(suiteName: UUID().uuidString)!
  return defaults
}

private func repo(_ owner: String, _ name: String, filter: BranchFilter = .mine) -> WatchedRepo {
  WatchedRepo(owner: owner, name: name, defaultBranch: "main", filter: filter)
}

struct WatchListTests {
  @Test func startsEmptyWithoutStoredData() {
    #expect(WatchList(defaults: makeDefaults()).repos.isEmpty)
  }

  @Test func savesEveryChangeAndReloadsIt() {
    let defaults = makeDefaults()
    var list = WatchList(defaults: defaults)
    #expect(list.add(repo("swiftlang", "swift-format", filter: .all)) == .added)
    #expect(list.add(repo("vuhnger", "cight")) == .added)
    let reloaded = WatchList(defaults: defaults)
    #expect(reloaded.repos == list.repos)
    #expect(reloaded.repos.first?.filter == .all)
    #expect(reloaded.repos.first?.defaultBranch == "main")
  }

  @Test func holdsAtMostEightEntries() {
    let defaults = makeDefaults()
    var list = WatchList(defaults: defaults)
    for index in 1...8 {
      #expect(list.add(repo("o", "r\(index)")) == .added)
    }
    #expect(list.add(repo("o", "r9")) == .full)
    #expect(list.repos.count == 8)
    #expect(WatchList(defaults: defaults).repos.count == 8)
  }

  @Test func rejectsDuplicatesCaseInsensitively() {
    var list = WatchList(defaults: makeDefaults())
    #expect(list.add(repo("swiftlang", "swift-format")) == .added)
    #expect(list.add(repo("SwiftLang", "Swift-Format", filter: .all)) == .duplicate)
    #expect(list.repos.count == 1)
    #expect(list.repos[0].filter == .mine)
  }

  @Test func aFullListReportsDuplicateBeforeFull() {
    var list = WatchList(defaults: makeDefaults())
    for index in 1...8 {
      _ = list.add(repo("o", "r\(index)"))
    }
    #expect(list.add(repo("O", "R1")) == .duplicate)
  }

  @Test func removesAnEntryCaseInsensitivelyAndPersists() {
    let defaults = makeDefaults()
    var list = WatchList(defaults: defaults)
    _ = list.add(repo("a", "one"))
    _ = list.add(repo("a", "two"))
    list.remove(owner: "A", name: "ONE")
    #expect(list.repos.map(\.name) == ["two"])
    #expect(WatchList(defaults: defaults).repos.map(\.name) == ["two"])
  }

  @Test func changesTheFilterOfOneEntryAndPersists() {
    let defaults = makeDefaults()
    var list = WatchList(defaults: defaults)
    _ = list.add(repo("a", "one"))
    _ = list.add(repo("a", "two"))
    list.setFilter(.defaultBranch, owner: "a", name: "two")
    let reloaded = WatchList(defaults: defaults)
    #expect(reloaded.repos.map(\.filter) == [.mine, .defaultBranch])
  }

  @Test func loadsDuplicatesAndOverflowFromStoredDataCleanly() throws {
    let defaults = makeDefaults()
    var stored = (1...12).map { repo("o", "r\($0)") }
    stored.insert(repo("O", "R3"), at: 5)
    defaults.set(try JSONEncoder().encode(stored), forKey: WatchList.key)
    let list = WatchList(defaults: defaults)
    #expect(list.repos.count == 8)
    #expect(Set(list.repos.map { $0.name.lowercased() }).count == 8)
    #expect(list.repos.map(\.name).prefix(3) == ["r1", "r2", "r3"])
  }

  @Test func loadsCorruptDataAsAnEmptyList() {
    let defaults = makeDefaults()
    defaults.set(Data([0xFF, 0x00, 0x7B, 0x22]), forKey: WatchList.key)
    #expect(WatchList(defaults: defaults).repos.isEmpty)
  }

  @Test(arguments: [
    #"["swiftlang/swift-format"]"#,
    #"{"repos": []}"#,
    #"[{"owner": "a", "name": "b"}]"#,
    #"[{"owner": "a", "name": "b", "defaultBranch": "main", "filter": "nonsense"}]"#,
    "not json",
  ])
  func loadsOldOrForeignDataAsAnEmptyList(json: String) {
    let defaults = makeDefaults()
    defaults.set(Data(json.utf8), forKey: WatchList.key)
    #expect(WatchList(defaults: defaults).repos.isEmpty)
  }

  @Test func loadsWrongTypedValuesAsAnEmptyList() {
    let defaults = makeDefaults()
    defaults.set("a string", forKey: WatchList.key)
    #expect(WatchList(defaults: defaults).repos.isEmpty)
    defaults.set(42, forKey: WatchList.key)
    #expect(WatchList(defaults: defaults).repos.isEmpty)
  }

  @Test(arguments: [BranchFilter.defaultBranch, .mine, .all])
  func branchFiltersSurviveEncoding(filter: BranchFilter) throws {
    let data = try JSONEncoder().encode(filter)
    #expect(try JSONDecoder().decode(BranchFilter.self, from: data) == filter)
  }
}
