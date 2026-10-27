import CightCore
import Foundation

struct WatchStore {
  var repos: @MainActor () -> [WatchedRepo]
  var add: @MainActor (WatchedRepo) -> WatchList.AddOutcome
  var remove: @MainActor (_ owner: String, _ name: String) -> Void
  var setFilter: @MainActor (_ filter: BranchFilter, _ owner: String, _ name: String) -> Void
}

@MainActor
private final class StandInList {
  var list: WatchList

  init(defaults: UserDefaults) {
    list = WatchList(defaults: defaults)
  }
}

extension WatchStore {
  @MainActor
  static func standIn(defaults: UserDefaults) -> WatchStore {
    let box = StandInList(defaults: defaults)
    return WatchStore(
      repos: { box.list.repos },
      add: { box.list.add($0) },
      remove: { box.list.remove(owner: $0, name: $1) },
      setFilter: { box.list.setFilter($0, owner: $1, name: $2) })
  }
}
