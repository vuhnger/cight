import CightCore
import SwiftUI

let amber = Color(red: 0.88, green: 0.66, blue: 0.16)

enum GlyphKind: Equatable {
  case passed
  case failed
  case queued
  case running(Double?)
  case overdue
  case neutral
  case warning
  case signedOut

  init(_ glyph: MenuBarGlyph?) {
    switch glyph {
    case .passed: self = .passed
    case .failed: self = .failed
    case .queued: self = .queued
    case .running(let progress): self = .running(progress)
    case .overdue: self = .overdue
    case .signedOut: self = .signedOut
    case nil: self = .neutral
    }
  }

  init(_ state: RunState) {
    switch state {
    case .passed: self = .passed
    case .failed: self = .failed
    case .queued: self = .queued
    case .running: self = .running(nil)
    case .neutral: self = .neutral
    }
  }
}

struct PieShape: Shape {
  let fraction: Double

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    path.move(to: center)
    path.addArc(
      center: center, radius: rect.width / 2, startAngle: .degrees(-90),
      endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
    path.closeSubpath()
    return path
  }
}

struct StateGlyph: View {
  let kind: GlyphKind
  var size: CGFloat = 14

  var body: some View {
    content.frame(width: size, height: size)
  }

  @ViewBuilder private var content: some View {
    switch kind {
    case .passed: symbol("checkmark.circle.fill", .white, .green)
    case .failed: symbol("xmark.circle.fill", .white, .red)
    case .queued:
      Image(systemName: "clock").resizable().fontWeight(.semibold).foregroundStyle(amber)
    case .running(let fraction): pie(fraction, amber)
    case .overdue: pie(1, .orange)
    case .neutral:
      Image(systemName: "circle.dashed").resizable().foregroundStyle(.secondary)
    case .warning:
      Image(systemName: "exclamationmark.triangle.fill").resizable().scaledToFit()
        .foregroundStyle(.orange)
    case .signedOut:
      Image(systemName: "lock.fill").resizable().scaledToFit().foregroundStyle(.red)
    }
  }

  private func symbol(_ name: String, _ primary: Color, _ secondary: Color) -> some View {
    Image(systemName: name).resizable().symbolRenderingMode(.palette)
      .foregroundStyle(primary, secondary)
  }

  private func pie(_ fraction: Double?, _ color: Color) -> some View {
    ZStack {
      Circle().strokeBorder(color, lineWidth: max(1.5, size * 0.12))
      if let fraction {
        PieShape(fraction: fraction).fill(color).padding(size * 0.24)
      } else {
        Circle().fill(color).frame(width: size * 0.36, height: size * 0.36)
      }
    }
  }
}

struct MenuBarStrip: View {
  let glyphs: [MenuBarGlyph]

  var body: some View {
    HStack(spacing: 5) {
      ForEach(Array(glyphs.enumerated()), id: \.offset) { _, glyph in
        StateGlyph(kind: GlyphKind(glyph), size: 15)
      }
    }
    .padding(.horizontal, 2)
    .environment(\.colorScheme, .dark)
  }
}
