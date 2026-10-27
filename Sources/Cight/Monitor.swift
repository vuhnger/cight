import AppKit
import CightCore
import Observation

private struct Fetched: Sendable {
  let id: String
  let group: RepoGroup?
  let rawRuns: [WorkflowRun]
  let etas: [Int: ETAEstimate]
}

private struct Outcome: Sendable {
  let watched: WatchedRepo
  let result: Result<Fetched, GitHubError>
}

@MainActor @Observable
final class Monitor {
  private(set) var repos: [RepoModel] = []
  private(set) var notice: PanelNotice?
  private(set) var glyphs: [MenuBarGlyph] = []
  var onEvents: (([RunEvent]) -> Void)?

  @ObservationIgnored private var watchList: WatchList
  @ObservationIgnored private let client: GitHubClient
  @ObservationIgnored private var viewer: String?
  @ObservationIgnored private var rows: [Int: RunRowModel] = [:]
  @ObservationIgnored private var models: [String: RepoModel] = [:]
  @ObservationIgnored private var menuInputs: [String: MenuBarRepo] = [:]
  @ObservationIgnored private var trackers: [String: RunTracker] = [:]
  @ObservationIgnored private var lastUpdated: Date?
  @ObservationIgnored private var lastPollStart = Date.distantPast
  @ObservationIgnored private var failures = 0
  @ObservationIgnored private var panelVisible = false
  @ObservationIgnored private var hasActiveRun = false
  @ObservationIgnored private var woke = false
  @ObservationIgnored private var forced = false
  @ObservationIgnored private var loop: Task<Void, Never>?
  @ObservationIgnored private var sleeper: Task<Void, Never>?
  @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?

  var watched: [WatchedRepo] { watchList.repos }

  var showsRepos: Bool {
    switch notice {
    case .ghMissing, .signedOut, .nothingWatched: false
    default: true
    }
  }

  init(defaults: UserDefaults = .standard) {
    watchList = WatchList(defaults: defaults)
    client = GitHubClient(tokenProvider: { await GhTokenReader.read() })
    notice = watchList.repos.isEmpty ? .nothingWatched : nil
  }

  func start() {
    guard loop == nil else { return }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.woke = true
        self?.nudge()
      }
    }
    loop = Task { await run() }
  }

  func retry() {
    forced = true
    nudge()
  }

  func panelVisibilityChanged(_ visible: Bool) {
    panelVisible = visible
    guard visible else { return }
    if Date().timeIntervalSince(lastPollStart) > 1 { forced = true }
    nudge()
  }

  @discardableResult
  func add(_ repo: WatchedRepo) -> WatchList.AddOutcome {
    let outcome = watchList.add(repo)
    if outcome == .added { watchListChanged() }
    return outcome
  }

  func remove(owner: String, name: String) {
    watchList.remove(owner: owner, name: name)
    trackers["\(owner)/\(name)".lowercased()] = nil
    watchListChanged()
  }

  func setFilter(_ filter: BranchFilter, owner: String, name: String) {
    watchList.setFilter(filter, owner: owner, name: name)
    trackers["\(owner)/\(name)".lowercased()] = nil
    watchListChanged()
  }

  private func watchListChanged() {
    forced = true
    nudge()
  }

  private func nudge() {
    sleeper?.cancel()
  }

  private func run() async {
    while !Task.isCancelled {
      lastPollStart = Date()
      let error = await poll()
      let finished = Date()
      let jitter = Double.random(in: 0...1)
      while !Task.isCancelled {
        let delay = PollPolicy.delay(
          after: error, failures: failures, panelVisible: panelVisible,
          hasActiveRun: hasActiveRun, wokeFromSleep: woke, now: Date(), jitter: jitter)
        let remaining = finished.addingTimeInterval(delay).timeIntervalSinceNow
        if remaining <= 0 || forced { break }
        let sleep = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(remaining)) }
        sleeper = sleep
        await sleep.value
      }
      woke = false
      forced = false
    }
  }

  private func poll() async -> GitHubError? {
    let list = watchList.repos
    guard !list.isEmpty else {
      apply(outcomes: [], errors: [])
      return nil
    }
    let outcomes: [Outcome]
    do {
      let login = try await viewerLogin()
      outcomes = await withTaskGroup(of: Outcome.self) { [client] group in
        for watched in list {
          group.addTask { await Self.fetch(client: client, watched: watched, viewer: login) }
        }
        var all: [Outcome] = []
        for await outcome in group { all.append(outcome) }
        return all
      }
    } catch {
      let failure = error as? GitHubError ?? .transport(.unknown)
      failures = PollPolicy.failures(after: failure, previous: failures)
      apply(outcomes: [], errors: [failure])
      return failure
    }
    let errors = outcomes.compactMap { outcome -> GitHubError? in
      if case .failure(let error) = outcome.result { error } else { nil }
    }
    let primary =
      errors.first { $0 == .unauthorized }
      ?? errors.first { if case .rateLimited = $0 { true } else { false } }
      ?? errors.first { $0 != .notFound }
    failures = PollPolicy.failures(after: primary, previous: failures)
    apply(outcomes: outcomes, errors: errors)
    return primary
  }

  private func viewerLogin() async throws -> String {
    if let viewer { return viewer }
    let login = try await client.viewer().login
    viewer = login
    return login
  }

  private nonisolated static func fetch(
    client: GitHubClient, watched: WatchedRepo, viewer: String
  ) async -> Outcome {
    do {
      let repo = try await client.repo(owner: watched.owner, name: watched.name)
      let runs = try await client.runs(owner: watched.owner, name: watched.name)
      let group = RunGrouping.groups(
        [
          RepoRuns(
            id: repo.id, fullName: repo.fullName, defaultBranch: repo.defaultBranch, runs: runs)
        ],
        viewer: viewer, filter: watched.filter
      ).first
      var etas: [Int: ETAEstimate] = [:]
      for run in group?.branches.flatMap(\.runs) ?? [] where run.state == .running {
        etas[run.id] = ETA.estimate(for: run, among: runs)
      }
      let fetched = Fetched(
        id: "\(watched.owner)/\(watched.name)".lowercased(), group: group, rawRuns: runs,
        etas: etas)
      return Outcome(watched: watched, result: .success(fetched))
    } catch let error as GitHubError {
      return Outcome(watched: watched, result: .failure(error))
    } catch {
      return Outcome(watched: watched, result: .failure(.transport(.unknown)))
    }
  }

  private func apply(outcomes: [Outcome], errors: [GitHubError]) {
    let list = watchList.repos
    let now = Date()
    if !outcomes.isEmpty,
      outcomes.contains(where: { if case .success = $0.result { true } else { false } })
    {
      lastUpdated = now
    }
    var events: [RunEvent] = []
    var live = Set<Int>()
    var ordered: [(model: RepoModel, rank: Int, newest: Date)] = []
    for watched in list {
      let id = "\(watched.owner)/\(watched.name)".lowercased()
      let model = models[id] ?? RepoModel(owner: watched.owner, name: watched.name)
      models[id] = model
      guard let outcome = outcomes.first(where: { $0.watched == watched }) else {
        if let last = menuInputs[id] { live.formUnion(last.visible.map(\.id)) }
        ordered.append((model, rank(of: model), model.newest ?? .distantPast))
        continue
      }
      switch outcome.result {
      case .success(let fetched):
        if model.problem != nil { model.problem = nil }
        let visible = fetched.group?.branches.flatMap(\.runs) ?? []
        live.formUnion(visible.map(\.id))
        apply(fetched, to: model)
        menuInputs[id] = MenuBarRepo(visible: visible, history: fetched.rawRuns)
        var tracker = trackers[id] ?? RunTracker()
        events += tracker.ingest(repo: id, runs: fetched.rawRuns, filter: watched.filter)
        trackers[id] = tracker
      case .failure(.notFound):
        model.problem = .gone
        model.branches = []
        model.glyph = nil
        model.newest = nil
        menuInputs[id] = nil
      case .failure:
        if let last = menuInputs[id] { live.formUnion(last.visible.map(\.id)) }
      }
      ordered.append((model, rank(of: model), model.newest ?? .distantPast))
    }
    ordered.sort { ($0.rank, $1.newest) < ($1.rank, $0.newest) }
    let newOrder = ordered.map(\.model)
    if newOrder.map(\.id) != repos.map(\.id) { repos = newOrder }
    let ids = Set(list.map { "\($0.owner)/\($0.name)".lowercased() })
    models = models.filter { ids.contains($0.key) }
    menuInputs = menuInputs.filter { ids.contains($0.key) }
    rows = rows.filter { live.contains($0.key) }

    let unauthorized = errors.contains(.unauthorized)
    let newNotice = NoticePolicy.notice(
      ghInstalled: GhTokenReader.defaultPaths.contains(where: FileManager.default.isExecutableFile),
      tokenAvailable: true, watchedCount: list.count, errors: errors, lastUpdated: lastUpdated)
    if newNotice != notice { notice = newNotice }
    let newGlyphs = MenuBarGlyphs.glyphs(
      repos: newOrder.compactMap { menuInputs[$0.id] },
      signedOut: unauthorized || newNotice == .ghMissing,
      now: now)
    if newGlyphs != glyphs { glyphs = newGlyphs }
    hasActiveRun = menuInputs.values.contains {
      $0.visible.contains { $0.state == .running || $0.state == .queued }
    }
    if !events.isEmpty { onEvents?(events) }
  }

  private func rank(of model: RepoModel) -> Int {
    if model.problem != nil { return 5 }
    return switch model.glyph {
    case .failed: 0
    case .running, .overdue: 1
    case .queued: 2
    case .passed: 3
    case .signedOut, nil: 4
    }
  }

  private func apply(_ fetched: Fetched, to model: RepoModel) {
    let branches = (fetched.group?.branches ?? []).map { branch in
      BranchModel(
        name: branch.branch,
        rows: branch.runs.map { run in
          let eta = fetched.etas[run.id]
          if let row = rows[run.id] {
            row.update(run: run, eta: eta)
            return row
          }
          let row = RunRowModel(run: run, eta: eta)
          rows[run.id] = row
          return row
        })
    }
    if branches != model.branches { model.branches = branches }
    let visible = fetched.group?.branches.flatMap(\.runs) ?? []
    let glyph = MenuBarGlyphs.glyph(
      for: MenuBarRepo(visible: visible, history: fetched.rawRuns), now: Date())
    if glyph != model.glyph { model.glyph = glyph }
    let newest = visible.map(\.activityDate).max()
    if newest != model.newest { model.newest = newest }
  }
}
