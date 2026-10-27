import CoreGraphics

public enum PanelPlacement {
  public static let gap: CGFloat = 1
  public static let leadingOffset: CGFloat = 4
  public static let margin: CGFloat = 8

  public struct Screen: Equatable, Sendable {
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(frame: CGRect, visibleFrame: CGRect) {
      self.frame = frame
      self.visibleFrame = visibleFrame
    }
  }

  public struct Insets: Equatable, Sendable {
    public let leading: CGFloat
    public let trailing: CGFloat
    public let top: CGFloat

    public init(leading: CGFloat, trailing: CGFloat, top: CGFloat) {
      self.leading = leading
      self.trailing = trailing
      self.top = top
    }
  }

  public static func origin(
    icon: CGRect, screens: [Screen], insets: Insets, panelSize: CGSize
  ) -> CGPoint? {
    let center = CGPoint(x: icon.midX, y: icon.midY)
    guard let screen = screens.first(where: { $0.frame.contains(center) }) else { return nil }
    let visible = screen.visibleFrame
    let cardWidth = panelSize.width - insets.leading - insets.trailing
    let lowest = visible.minX + margin
    let highest = max(lowest, visible.maxX - margin - cardWidth)
    let cardLeft = min(max(icon.minX - leadingOffset, lowest), highest)
    return CGPoint(
      x: cardLeft - insets.leading,
      y: icon.minY - gap + insets.top - panelSize.height)
  }
}
