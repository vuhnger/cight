import AppKit
import CightCore
import SwiftUI

enum Metrics {
  static let panelWidth: CGFloat = 420
  static let toastWidth: CGFloat = 340
  static let outerPadding: CGFloat = 10
  static let cardSpacing: CGFloat = 10
  static let cardRadius: CGFloat = 22
  static let cardHorizontal: CGFloat = 16
  static let cardVertical: CGFloat = 12
  static let header: CGFloat = 22
  static let indent: CGFloat = 26
  static let branchTop: CGFloat = 8
  static let pill: CGFloat = 20
  static let row: CGFloat = 24
  static let bar: CGFloat = 8
  static let problem: CGFloat = 38
  static let notice: CGFloat = 64
  static let noticeGlyph: CGFloat = 20
  static let headerGlyph: CGFloat = 16
  static let rowGlyph: CGFloat = 13
  static let menuBarGlyph: CGFloat = 15
  static let settingsInnerSpacing: CGFloat = 6
  static let glyphGap: CGFloat = 10
  static var panelRadius: CGFloat { cardRadius + outerPadding }
  static let tileFill = Color.white.opacity(0.08)
  static let noticeFill = Color.orange.opacity(0.25)

  @MainActor
  static func height(of repo: RepoModel) -> CGFloat {
    var total = cardVertical * 2 + header
    if repo.problem != nil { return total + problem }
    guard repo.expanded else { return total }
    for branch in repo.branches {
      total += branchTop + pill
      for row in branch.rows { total += rowHeight(row) }
    }
    return total
  }

  @MainActor
  static func rowHeight(_ row: RunRowModel) -> CGFloat {
    row.state == .running && row.median != nil ? Self.row + bar : Self.row
  }

  @MainActor
  static func height(of monitor: Monitor) -> CGFloat {
    var heights: [CGFloat] = []
    if monitor.notice != nil { heights.append(notice) }
    if monitor.showsRepos { heights += monitor.repos.map(height(of:)) }
    let gaps = CGFloat(max(0, heights.count - 1)) * cardSpacing
    return heights.reduce(0, +) + gaps + outerPadding * 2
  }
}

struct BlurBackground: NSViewRepresentable {
  let radius: CGFloat

  func makeNSView(context: Context) -> NSVisualEffectView {
    let view = NSVisualEffectView()
    view.blendingMode = .behindWindow
    view.state = .active
    view.material = .hudWindow
    view.appearance = NSAppearance(named: .darkAqua)
    view.wantsLayer = true
    view.layer?.cornerRadius = radius
    view.layer?.cornerCurve = .continuous
    view.layer?.masksToBounds = true
    return view
  }

  func updateNSView(_ view: NSVisualEffectView, context: Context) {
    view.layer?.cornerRadius = radius
  }
}

struct PanelRoot: View {
  let monitor: Monitor
  let open: (URL) -> Void

  var body: some View {
    let stale = isStale
    ScrollView(.vertical) {
      VStack(spacing: Metrics.cardSpacing) {
        if let notice = monitor.notice {
          NoticeCard(notice: notice, retry: monitor.retry)
        }
        if monitor.showsRepos {
          ForEach(monitor.repos) { repo in
            RepoCard(repo: repo, open: open)
              .grayscale(stale ? 1 : 0)
              .opacity(stale ? 0.6 : 1)
          }
        }
      }
      .padding(Metrics.outerPadding)
    }
    .scrollIndicators(.hidden)
    .focusEffectDisabled()
    .scrollBounceBehavior(.basedOnSize)
    .background(BlurBackground(radius: Metrics.panelRadius))
    .frame(width: Metrics.panelWidth, alignment: .top)
    .preferredColorScheme(.dark)
  }

  private var isStale: Bool {
    switch monitor.notice {
    case .offline, .unavailable, .rateLimited: true
    default: false
    }
  }
}

struct NoticeCard: View {
  let notice: PanelNotice
  let retry: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      StateGlyph(kind: glyph, size: Metrics.noticeGlyph)
      content
        .font(.callout)
        .lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
      if notice == .signedOut || notice == .gitLabSignedOut {
        Button("Retry", action: retry).buttonStyle(.borderedProminent)
      }
    }
    .padding(.horizontal, 16)
    .frame(height: Metrics.notice)
    .background(Metrics.noticeFill, in: .rect(cornerRadius: Metrics.cardRadius))
  }

  private var glyph: GlyphKind {
    notice == .signedOut || notice == .gitLabSignedOut ? .signedOut : .warning
  }

  @ViewBuilder private var content: some View {
    switch notice {
    case .signedOut:
      Text("GitHub rejected the token. Run gh auth login in Terminal.")
    case .gitLabSignedOut:
      Text("GitLab rejected the token. Run glab auth login in Terminal.")
    case .ghMissing:
      Text("The gh command is missing. Install it with brew install gh, then run gh auth login.")
    case .noRecentRuns:
      Text("No runs from you in the last 7 days.")
    case .rateLimited(let until):
      Text(
        "GitHub rate limit reached. Checking again at \(until.formatted(date: .omitted, time: .shortened))."
      )
    case .offline(let since):
      AgedText(prefix: "Offline.", since: since)
    case .unavailable(let since):
      AgedText(prefix: "GitHub is not responding.", since: since)
    }
  }
}

private struct AgedText: View {
  let prefix: String
  let since: Date?

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      if let since {
        Text("\(prefix) Last updated \(Formatting.relative(from: since, now: context.date)).")
      } else {
        Text(prefix)
      }
    }
  }
}

struct RepoCard: View {
  let repo: RepoModel
  let open: (URL) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if repo.problem != nil {
        Text("Repository not found, or your token lost access.")
          .font(.callout).foregroundStyle(.secondary)
          .lineLimit(2)
          .padding(.leading, Metrics.indent)
          .frame(height: Metrics.problem, alignment: .topLeading)
      } else if repo.expanded {
        ForEach(repo.branches) { branch in
          BranchPill(name: branch.name)
          ForEach(branch.rows) { RunRow(row: $0, open: open) }
        }
      }
    }
    .padding(.horizontal, Metrics.cardHorizontal)
    .padding(.vertical, Metrics.cardVertical)
    .frame(height: Metrics.height(of: repo), alignment: .top)
    .background(Metrics.tileFill, in: .rect(cornerRadius: Metrics.cardRadius))
  }

  private var header: some View {
    Button {
      repo.toggle()
    } label: {
      HStack(spacing: Metrics.glyphGap) {
        StateGlyph(
          kind: repo.problem != nil ? .warning : GlyphKind(repo.glyph), size: Metrics.headerGlyph)
        HStack(spacing: 0) {
          Text("\(repo.owner)/").foregroundStyle(.secondary)
          Text(repo.name).fontWeight(.semibold)
        }
        .lineLimit(1)
        Spacer(minLength: 8)
        if let newest = repo.newest {
          RelativeTime(date: newest).foregroundStyle(.secondary)
        }
        if repo.problem == nil {
          Image(systemName: repo.expanded ? "chevron.up" : "chevron.down")
            .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
      }
      .frame(height: Metrics.header)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(repo.problem != nil)
  }
}

struct BranchPill: View {
  let name: String

  var body: some View {
    Text(name)
      .font(.system(.caption, design: .monospaced))
      .foregroundStyle(.blue)
      .lineLimit(1)
      .padding(.horizontal, 7)
      .frame(height: Metrics.pill)
      .background(.blue.opacity(0.12), in: .capsule)
      .padding(.leading, Metrics.indent)
      .padding(.top, Metrics.branchTop)
  }
}

struct RelativeTime: View {
  let date: Date

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      Text(Formatting.relative(from: date, now: context.date)).monospacedDigit()
    }
  }
}

struct RunRow: View {
  let row: RunRowModel
  let open: (URL) -> Void

  var body: some View {
    Button {
      if let url = row.url { open(url) }
    } label: {
      VStack(spacing: 0) {
        HStack(spacing: 7) {
          RowGlyph(row: row)
          Text(row.workflow).fontWeight(.medium).lineLimit(1)
            .frame(width: row.workflowWidth, alignment: .leading).layoutPriority(1)
          if let number = row.pullRequest {
            Text("\(row.isMergeRequest ? "!" : "#")\(number)").monospacedDigit().foregroundStyle(
              .tertiary
            ).layoutPriority(2)
          }
          AvatarView(url: row.avatar, login: row.starter)
          Text(row.title).foregroundStyle(.secondary).lineLimit(1)
          Spacer(minLength: 8)
          RowTrailing(row: row).layoutPriority(2)
        }
        .frame(height: Metrics.row)
        if row.state == .running, row.median != nil {
          RowBar(row: row).frame(height: Metrics.bar, alignment: .top)
        }
      }
      .font(.callout)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.leading, Metrics.indent)
    .frame(height: Metrics.rowHeight(row))
  }
}

private struct RowGlyph: View {
  let row: RunRowModel

  var body: some View {
    if row.state == .running {
      TimelineView(.periodic(from: .now, by: 1)) { context in
        let progress = row.progress(at: context.date)
        StateGlyph(
          kind: progress?.isOverdue == true ? .overdue : .running(progress?.fraction),
          size: Metrics.rowGlyph
        )
        .animation(.linear(duration: 1), value: progress?.fraction)
      }
    } else {
      StateGlyph(kind: GlyphKind(row.state), size: Metrics.rowGlyph)
    }
  }
}

private struct RowTrailing: View {
  let row: RunRowModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      if row.state == .running {
        running(now: context.date)
      } else {
        Text(Formatting.relative(from: row.activityAt, now: context.date))
          .monospacedDigit().foregroundStyle(.tertiary)
      }
    }
  }

  private func running(now: Date) -> some View {
    let elapsed = now.timeIntervalSince(row.startedAt)
    let overdue = row.progress(at: now)?.isOverdue == true
    return HStack(spacing: 8) {
      Text(Formatting.duration(elapsed)).foregroundStyle(overdue ? .orange : amber)
      if let median = row.median {
        Text((row.samples < 3 ? "~" : "") + Formatting.remaining(median - elapsed))
          .foregroundStyle(overdue ? .orange : .secondary)
      }
    }
    .monospacedDigit()
  }
}

private struct RowBar: View {
  let row: RunRowModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let progress = row.progress(at: context.date)
      Capsule().fill(.quaternary).frame(height: 4)
        .overlay(alignment: .leading) {
          Capsule().fill(progress?.isOverdue == true ? Color.orange : amber)
            .scaleEffect(x: progress?.fraction ?? 0, y: 1, anchor: .leading)
            .animation(.linear(duration: 1), value: progress?.fraction)
        }
        .padding(.leading, 20)
    }
  }
}
