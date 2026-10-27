import AppKit
import CightCore
import Observation

private struct RepoMeta: Sendable {
  let repo: Repo
  let branches: Set<String>?
  let fetchedAt: Date
}

private struct Fetched: Sendable {
  let id: String
  let meta: RepoMeta
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
  private(set) var glyphs: [MenuBarGlyph] = [.idle]
  var onEvents: (([RunEvent]) -> Void)?
  var onSession: ((SessionState) -> Void)?

  @ObservationIgnored private var watchList: WatchList
  @ObservationIgnored let client: GitHubClient
  @ObservationIgnored private var viewer: String?
  @ObservationIgnored private var metas: [String: RepoMeta] = [:]
  @ObservationIgnored private var ghInstalled = true
  @ObservationIgnored private var lastError: GitHubError?
  @ObservationIgnored private var pollTask: Task<Void, Never>?
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

  init(
    defaults: UserDefaults = .standard,
    client: GitHubClient = GitHubClient(tokenProvider: { await GhTokenReader.read() })
  ) {
    watchList = WatchList(defaults: defaults)
    self.client = client
    notice = watchList.repos.isEmpty ? .nothingWatched : nil
  }

  func start() {
    guard loop == nil else { return }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.woke = true
        self?.pollTask?.cancel()
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
      let task = Task { await poll() }
      pollTask = task
      await task.value
      let finished = Date()
      let error = lastError
      let jitter = Double.random(in: 0...1)
      while !Task.isCancelled {
        let delay = PollPolicy.delay(
          after: error, failures: failures, panelVisible: panelVisible,
          hasActiveRun: hasActiveRun, wokeFromSleep: woke, now: finished, jitter: jitter)
        let remaining = finished.addingTimeInterval(delay).timeIntervalSinceNow
        if remaining <= 0 || (forced && PollPolicy.allowsForcedPoll(after: error)) { break }
        let sleep = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(remaining)) }
        sleeper = sleep
        await sleep.value
      }
      if woke { await NetworkGate.waitUntilSatisfied(timeout: .seconds(2)) }
      woke = false
      forced = false
    }
  }

  private func poll() async {
    let list = watchList.repos
    guard !list.isEmpty else {
      lastError = nil
      apply(outcomes: [], errors: [])
      return
    }
    let outcomes: [Outcome]
    do {
      let login = try await viewerLogin()
      let known = metas
      let now = Date()
      outcomes = await withTaskGroup(of: Outcome.self) { [client] group in
        for watched in list {
          let id = "\(watched.owner)/\(watched.name)".lowercased()
          group.addTask {
            await Self.fetch(
              client: client, watched: watched, viewer: login, cached: known[id], now: now)
          }
        }
        var all: [Outcome] = []
        for await outcome in group { all.append(outcome) }
        return all
      }
    } catch {
      guard !(error is CancellationError), !Task.isCancelled else { return }
      let failure = error as? GitHubError ?? .transport(.unknown)
      await finish(outcomes: [], errors: [failure])
      return
    }
    guard !Task.isCancelled else { return }
    let errors = outcomes.compactMap { outcome -> GitHubError? in
      if case .failure(let error) = outcome.result { error } else { nil }
    }
    await finish(outcomes: outcomes, errors: errors)
  }

  private func finish(outcomes: [Outcome], errors: [GitHubError]) async {
    let primary =
      errors.first { $0 == .unauthorized }
      ?? errors.first { if case .rateLimited = $0 { true } else { false } }
      ?? errors.first { $0 != .notFound }
    if primary == .unauthorized {
      viewer = nil
      ghInstalled = await Task.detached { GhTokenReader.isInstalled() }.value
    }
    failures = PollPolicy.failures(after: primary, previous: failures)
    lastError = primary
    apply(outcomes: outcomes, errors: errors)
  }

  private func viewerLogin() async throws -> String {
    if let viewer { return viewer }
    let login = try await client.viewer().login
    viewer = login
    return login
  }

  private nonisolated static let metaLifetime: TimeInterval = 300

  private nonisolated static func fetch(
    client: GitHubClient, watched: WatchedRepo, viewer: String, cached: RepoMeta?, now: Date
  ) async -> Outcome {
    do {
      let meta: RepoMeta
      if let cached, now.timeIntervalSince(cached.fetchedAt) < metaLifetime {
        meta = cached
      } else {
        let repo = try await client.repo(owner: watched.owner, name: watched.name)
        let branches = try? await client.branches(owner: watched.owner, name: watched.name)
        meta = RepoMeta(repo: repo, branches: branches ?? cached?.branches, fetchedAt: now)
      }
      let runs = try await client.runs(owner: watched.owner, name: watched.name)
      let group = RunGrouping.groups(
        [
          RepoRuns(
            id: meta.repo.id, fullName: meta.repo.fullName,
            defaultBranch: meta.repo.defaultBranch, runs: runs, liveBranches: meta.branches)
        ],
        viewer: viewer, filter: watched.filter
      ).first
      var etas: [Int: ETAEstimate] = [:]
      for run in group?.branches.flatMap(\.runs) ?? [] where run.state == .running {
        etas[run.id] = ETA.estimate(for: run, among: runs)
      }
      let fetched = Fetched(
        id: "\(watched.owner)/\(watched.name)".lowercased(), meta: meta, group: group,
        rawRuns: runs, etas: etas)
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
        metas[id] = fetched.meta
        let visible = fetched.group?.branches.flatMap(\.runs) ?? []
        live.formUnion(visible.map(\.id))
        apply(fetched, to: model)
        menuInputs[id] = MenuBarRepo(visible: visible, history: fetched.rawRuns)
        var tracker = trackers[id] ?? RunTracker()
        events += tracker.ingest(repo: id, runs: fetched.rawRuns, filter: watched.filter)
        trackers[id] = tracker
      case .failure(.notFound):
        model.problem = .gone
        metas[id] = nil
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
    metas = metas.filter { ids.contains($0.key) }
    menuInputs = menuInputs.filter { ids.contains($0.key) }
    rows = rows.filter { live.contains($0.key) }

    let unauthorized = errors.contains(.unauthorized)
    let newNotice = NoticePolicy.notice(
      ghInstalled: ghInstalled,
      tokenAvailable: true, watchedCount: list.count, errors: errors, lastUpdated: lastUpdated)
    if newNotice != notice { notice = newNotice }
    let newGlyphs = MenuBarGlyphs.glyphs(
      repos: newOrder.compactMap { menuInputs[$0.id] },
      signedOut: unauthorized || newNotice == .ghMissing,
      now: now)
    if newGlyphs != glyphs { glyphs = newGlyphs }
    onSession?(
      SessionPolicy.sample(
        signedOutSignal: unauthorized || newNotice == .ghMissing,
        anySuccess: outcomes.contains { if case .success = $0.result { true } else { false } }))
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
    case .signedOut, .idle, nil: 4
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
