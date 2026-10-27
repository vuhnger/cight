import CoreGraphics
import Testing

@testable import CightCore

private let main = PanelPlacement.Screen(
  frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
  visibleFrame: CGRect(x: 0, y: 0, width: 1728, height: 1084))
private let second = PanelPlacement.Screen(
  frame: CGRect(x: 1728, y: 0, width: 1920, height: 1080),
  visibleFrame: CGRect(x: 1728, y: 0, width: 1920, height: 1055))
private let size = CGSize(width: 420, height: 200)
private let inset = PanelPlacement.Insets(leading: 10, trailing: 10, top: 10)

private func place(icon: CGRect, screens: [PanelPlacement.Screen] = [main]) -> CGPoint? {
  PanelPlacement.origin(icon: icon, screens: screens, insets: inset, panelSize: size)
}

@Suite struct PanelPlacementTests {
  @Test func cardSitsLikeANativeMenuUnderTheIcon() throws {
    let icon = CGRect(x: 1000, y: 1084, width: 34, height: 33)
    let origin = try #require(place(icon: icon))
    let card = CGRect(
      x: origin.x + inset.leading, y: origin.y, width: size.width - 20, height: size.height - 10)
    #expect(card.minX == icon.minX - PanelPlacement.leadingOffset)
    #expect(card.maxY == icon.minY - PanelPlacement.gap)
  }

  @Test func shiftsLeftNearTheRightEdge() throws {
    let icon = CGRect(x: 1700, y: 1084, width: 28, height: 33)
    let origin = try #require(place(icon: icon))
    #expect(
      origin.x + size.width - inset.trailing == main.visibleFrame.maxX - PanelPlacement.margin)
  }

  @Test func shiftsRightNearTheLeftEdge() throws {
    let icon = CGRect(x: 2, y: 1084, width: 28, height: 33)
    let origin = try #require(place(icon: icon))
    #expect(origin.x + inset.leading == main.visibleFrame.minX + PanelPlacement.margin)
  }

  @Test func usesTheScreenTheIconIsOn() throws {
    let icon = CGRect(x: 3000, y: 1055, width: 34, height: 25)
    let origin = try #require(place(icon: icon, screens: [main, second]))
    #expect(origin.x + inset.leading == icon.minX - PanelPlacement.leadingOffset)
    #expect(origin.y + size.height - inset.top == icon.minY - PanelPlacement.gap)
  }

  @Test func clampsAgainstTheSecondScreenRightEdge() throws {
    let icon = CGRect(x: 3630, y: 1055, width: 34, height: 25)
    let origin = try #require(place(icon: icon, screens: [main, second]))
    #expect(
      origin.x + size.width - inset.trailing == second.visibleFrame.maxX - PanelPlacement.margin)
  }

  @Test func returnsNothingWhenNoScreenHoldsTheIcon() {
    let icon = CGRect(x: 9000, y: 9000, width: 34, height: 25)
    #expect(place(icon: icon, screens: [main, second]) == nil)
  }
}
