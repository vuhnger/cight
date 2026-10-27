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
  let repo: Repo
  let result: Result<Fetched, GitHubError>
}

@MainActor @Observable
final class Monitor {
  private(set) var repos: [RepoModel] = []
  private(set) var notice: PanelNotice?
  private(set) var glyphs: [MenuBarGlyph] = [.idle]
  var onEvents: (([RunEvent]) -> Void)?
  var onSession: ((SessionState) -> Void)?

  @ObservationIgnored private var discovered: [Repo] = []
  @ObservationIgnored private var lastDiscovery = Date.distantPast
  @ObservationIgnored private var discoveryForced = true
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

  var showsRepos: Bool {
    switch notice {
    case .ghMissing, .signedOut, .noRecentRuns: false
    default: true
    }
  }

  init(
    client: GitHubClient = GitHubClient(tokenProvider: { await GhTokenReader.read() })
  ) {
    self.client = client
  }

  func start() {
    guard loop == nil else { return }
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.woke = true
        self?.discoveryForced = true
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
    if !visible { for model in models.values { model.userExpanded = nil } }
    guard visible else { return }
    if Date().timeIntervalSince(lastPollStart) > 1 { forced = true }
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
    let login: String
    do {
      login = try await viewerLogin()
    } catch {
      guard !(error is CancellationError), !Task.isCancelled else { return }
      await finish(outcomes: [], errors: [error as? GitHubError ?? .transport(.unknown)])
      return
    }
    var errors: [GitHubError] = []
    let now = Date()
    if discoveryForced || now.timeIntervalSince(lastDiscovery) >= Self.discoveryInterval {
      let result = await RepoDiscovery.discover(
        previous: discovered, now: now,
        candidates: { [client] in try await client.repos() },
        latestRun: { [client] repo in
          let parts = repo.fullName.split(separator: "/").map(String.init)
          guard parts.count == 2 else { return nil }
          return try await client.latestRun(
            owner: parts[0], name: parts[1], actor: login,
            since: now.addingTimeInterval(-RepoDiscovery.window))
        })
      guard !Task.isCancelled else { return }
      discovered = result.repos
      if let error = result.error {
        errors.append(error)
      } else {
        lastDiscovery = now
        discoveryForced = false
      }
    }
    let list = discovered
    let known = metas
    let outcomes = await withTaskGroup(of: Outcome.self) { [client] group in
      for repo in list {
        group.addTask {
          await Self.fetch(
            client: client, repo: repo, viewer: login, cached: known[repo.key], now: now)
        }
      }
      var all: [Outcome] = []
      for await outcome in group { all.append(outcome) }
      return all
    }
    guard !Task.isCancelled else { return }
    errors += outcomes.compactMap { outcome -> GitHubError? in
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
  private nonisolated static let discoveryInterval: TimeInterval = 300

  private nonisolated static func fetch(
    client: GitHubClient, repo: Repo, viewer: String, cached: RepoMeta?, now: Date
  ) async -> Outcome {
    do {
      let meta: RepoMeta
      if let cached, now.timeIntervalSince(cached.fetchedAt) < metaLifetime {
        meta = cached
      } else {
        let branches = try? await client.branches(owner: repo.owner, name: repo.name)
        meta = RepoMeta(repo: repo, branches: branches ?? cached?.branches, fetchedAt: now)
      }
      let runs = try await client.runs(owner: repo.owner, name: repo.name)
      let group = RunGrouping.groups(
        [
          RepoRuns(
            id: meta.repo.id, fullName: meta.repo.fullName,
            defaultBranch: meta.repo.defaultBranch, runs: runs, liveBranches: meta.branches)
        ],
        viewer: viewer
      ).first
      var etas: [Int: ETAEstimate] = [:]
      for run in group?.branches.flatMap(\.runs) ?? [] where run.state == .running {
        etas[run.id] = ETA.estimate(for: run, among: runs)
      }
      let fetched = Fetched(
        id: repo.key, meta: meta, group: group,
        rawRuns: runs, etas: etas)
      return Outcome(repo: repo, result: .success(fetched))
    } catch let error as GitHubError {
      return Outcome(repo: repo, result: .failure(error))
    } catch {
      return Outcome(repo: repo, result: .failure(.transport(.unknown)))
    }
  }

  private func apply(outcomes: [Outcome], errors: [GitHubError]) {
    let list = discovered
    let now = Date()
    if !outcomes.isEmpty,
      outcomes.contains(where: { if case .success = $0.result { true } else { false } })
    {
      lastUpdated = now
    }
    var events: [RunEvent] = []
    var live = Set<Int>()
    var ordered: [RepoModel] = []
    for repo in list {
      let id = repo.key
      let model = models[id] ?? RepoModel(owner: repo.owner, name: repo.name)
      models[id] = model
      guard let outcome = outcomes.first(where: { $0.repo.id == repo.id }) else {
        if let last = menuInputs[id] { live.formUnion(last.visible.map(\.id)) }
        ordered.append(model)
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
        events += tracker.ingest(repo: id, runs: fetched.rawRuns)
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
      ordered.append(model)
    }
    let byId = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })
    let newOrder = RepoCardRules.newestFirst(ordered.map { (id: $0.id, newest: $0.newest) })
      .compactMap { byId[$0] }
    if newOrder.map(\.id) != repos.map(\.id) { repos = newOrder }
    let ids = Set(list.map(\.key))
    models = models.filter { ids.contains($0.key) }
    metas = metas.filter { ids.contains($0.key) }
    menuInputs = menuInputs.filter { ids.contains($0.key) }
    trackers = trackers.filter { ids.contains($0.key) }
    rows = rows.filter { live.contains($0.key) }

    let unauthorized = errors.contains(.unauthorized)
    let newNotice = NoticePolicy.notice(
      ghInstalled: ghInstalled,
      tokenAvailable: true, repoCount: list.count, errors: errors, lastUpdated: lastUpdated)
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

extension Repo {
  fileprivate var owner: String { String(fullName.split(separator: "/").first ?? "") }
  fileprivate var key: String { fullName.lowercased() }
}
