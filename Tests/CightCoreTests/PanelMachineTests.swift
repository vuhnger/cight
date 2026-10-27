import Foundation
import Testing

@testable import CightCore

private func timer(_ effects: [PanelEffect]) -> PanelTimer? {
  for case .schedule(let timer) in effects { return timer }
  return nil
}

private let onIcon = PanelInput.pointer(overIcon: true, overPanel: false)
private let onPanel = PanelInput.pointer(overIcon: false, overPanel: true)
private let away = PanelInput.pointer(overIcon: false, overPanel: false)

private func hoverOpen() -> PanelMachine {
  var machine = PanelMachine()
  let dwell = timer(machine.handle(onIcon))!
  _ = machine.handle(.timer(dwell))
  return machine
}

struct PanelMachineTests {
  @Test func dwellOpensTheHoverPanel() {
    var machine = PanelMachine()
    let effects = machine.handle(onIcon)
    let dwell = timer(effects)
    #expect(machine.phase == .opening)
    #expect(dwell?.kind == .dwell)
    #expect(dwell?.delay == PanelMachine.dwell)
    #expect(machine.handle(.timer(dwell!)) == [.show(pinned: false)])
    #expect(machine.phase == .hoverOpen)
  }

  @Test func leavingBeforeTheDwellEndsNeverOpens() {
    var machine = PanelMachine()
    let dwell = timer(machine.handle(onIcon))!
    #expect(machine.handle(away) == [.cancelTimer])
    #expect(machine.handle(.timer(dwell)).isEmpty)
    #expect(machine.phase == .hidden)
  }

  @Test func reenteringStartsAFreshDwellAndIgnoresTheStaleOne() {
    var machine = PanelMachine()
    let first = timer(machine.handle(onIcon))!
    _ = machine.handle(away)
    let second = timer(machine.handle(onIcon))!
    #expect(machine.handle(.timer(first)).isEmpty)
    #expect(machine.phase == .opening)
    #expect(machine.handle(.timer(second)) == [.show(pinned: false)])
  }

  @Test func repeatedPointerReportsOnTheIconKeepOneDwell() {
    var machine = PanelMachine()
    #expect(timer(machine.handle(onIcon)) != nil)
    #expect(machine.handle(onIcon).isEmpty)
    #expect(machine.phase == .opening)
  }

  @Test func closesAfterGraceOncePointerLeavesIconAndPanel() {
    var machine = hoverOpen()
    let grace = timer(machine.handle(away))!
    #expect(grace.kind == .grace)
    #expect(grace.delay == PanelMachine.grace)
    #expect(machine.phase == .closing)
    #expect(machine.handle(.timer(grace)) == [.hide])
    #expect(machine.phase == .hidden)
  }

  @Test func movingFromIconToPanelKeepsItOpen() {
    var machine = hoverOpen()
    #expect(machine.handle(onPanel).isEmpty)
    #expect(machine.phase == .hoverOpen)
  }

  @Test func returningDuringGraceCancelsTheClose() {
    var machine = hoverOpen()
    let grace = timer(machine.handle(away))!
    #expect(machine.handle(onPanel) == [.cancelTimer])
    #expect(machine.phase == .hoverOpen)
    #expect(machine.handle(.timer(grace)).isEmpty)
    #expect(machine.phase == .hoverOpen)
  }

  @Test func clickPinsAndPointerIsIgnoredWhilePinned() {
    var machine = PanelMachine()
    #expect(machine.handle(.iconClick) == [.show(pinned: true)])
    #expect(machine.phase == .pinned)
    #expect(machine.handle(away).isEmpty)
    #expect(machine.handle(onIcon).isEmpty)
    #expect(machine.phase == .pinned)
  }

  @Test func clickOnAHoverOpenPanelPinsIt() {
    var machine = hoverOpen()
    #expect(machine.handle(.iconClick) == [.show(pinned: true)])
    #expect(machine.phase == .pinned)
  }

  @Test func clickOrHotkeyWhilePinnedCloses() {
    var machine = PanelMachine()
    _ = machine.handle(.iconClick)
    #expect(machine.handle(.iconClick) == [.hide])
    #expect(machine.phase == .hidden)
    _ = machine.handle(.hotkey)
    #expect(machine.phase == .pinned)
    #expect(machine.handle(.hotkey) == [.hide])
    #expect(machine.phase == .hidden)
  }

  @Test func hotkeyOpensFromHiddenAndFromTheDwell() {
    var machine = PanelMachine()
    #expect(machine.handle(.hotkey) == [.show(pinned: true)])
    #expect(machine.phase == .pinned)
    var dwelling = PanelMachine()
    _ = dwelling.handle(onIcon)
    #expect(dwelling.handle(.hotkey).contains(.show(pinned: true)))
    #expect(dwelling.phase == .pinned)
  }

  @Test func escapeAndOutsideClickCloseEveryVisiblePhase() {
    for input in [PanelInput.escape, .outsideClick, .dismiss] {
      var pinned = PanelMachine()
      _ = pinned.handle(.hotkey)
      #expect(pinned.handle(input) == [.hide])
      var hover = hoverOpen()
      #expect(hover.handle(input) == [.hide])
      var closing = hoverOpen()
      _ = closing.handle(away)
      #expect(closing.handle(input).contains(.hide))
      #expect(closing.phase == .hidden)
    }
  }

  @Test func escapeAndOutsideClickDoNothingWhileHidden() {
    var machine = PanelMachine()
    #expect(machine.handle(.escape).isEmpty)
    #expect(machine.handle(.outsideClick).isEmpty)
    #expect(machine.phase == .hidden)
  }

  @Test func staleGraceTimerCannotCloseAPinnedPanel() {
    var machine = hoverOpen()
    let grace = timer(machine.handle(away))!
    _ = machine.handle(.iconClick)
    #expect(machine.handle(.timer(grace)).isEmpty)
    #expect(machine.phase == .pinned)
  }

  @Test func staleGraceTimerCannotCloseAHotkeyOpenedPanel() {
    var machine = hoverOpen()
    let grace = timer(machine.handle(away))!
    #expect(machine.handle(.hotkey).contains(.hide))
    #expect(machine.phase == .hidden)
    #expect(machine.handle(.hotkey) == [.show(pinned: true)])
    #expect(machine.handle(.timer(grace)).isEmpty)
    #expect(machine.phase == .pinned)
  }

  @Test func staleDwellTimerCannotReopenAfterEscape() {
    var machine = PanelMachine()
    let dwell = timer(machine.handle(onIcon))!
    _ = machine.handle(.hotkey)
    _ = machine.handle(.escape)
    #expect(machine.handle(.timer(dwell)).isEmpty)
    #expect(machine.phase == .hidden)
  }

  @Test func graceTimerFromAnEarlierCloseCannotCloseALaterHoverOpen() {
    var machine = hoverOpen()
    let oldGrace = timer(machine.handle(away))!
    _ = machine.handle(onIcon)
    let newGrace = timer(machine.handle(away))!
    #expect(machine.handle(.timer(oldGrace)).isEmpty)
    #expect(machine.phase == .closing)
    #expect(machine.handle(.timer(newGrace)) == [.hide])
  }

  @Test func closingByClickWhilePointerRestsOnTheIconDoesNotReopen() {
    var machine = PanelMachine()
    _ = machine.handle(onIcon)
    _ = machine.handle(.iconClick)
    _ = machine.handle(.iconClick)
    #expect(machine.handle(onIcon).isEmpty)
    #expect(machine.phase == .hidden)
    _ = machine.handle(away)
    #expect(timer(machine.handle(onIcon)) != nil)
    #expect(machine.phase == .opening)
  }

  @Test func escapeWhilePointerRestsOnTheIconDoesNotReopen() {
    var machine = hoverOpen()
    _ = machine.handle(.escape)
    #expect(machine.handle(onIcon).isEmpty)
    #expect(machine.phase == .hidden)
  }

  @Test func hoverWorksAgainAfterAGraceClose() {
    var machine = hoverOpen()
    let grace = timer(machine.handle(away))!
    _ = machine.handle(.timer(grace))
    let dwell = timer(machine.handle(onIcon))
    #expect(dwell?.kind == .dwell)
    #expect(machine.handle(.timer(dwell!)) == [.show(pinned: false)])
  }

  @Test func hoverWorksAfterAHotkeyOpenAndCloseWhileThePointerWasAway() {
    var machine = PanelMachine()
    _ = machine.handle(away)
    _ = machine.handle(.hotkey)
    _ = machine.handle(.hotkey)
    #expect(timer(machine.handle(onIcon))?.kind == .dwell)
    #expect(machine.phase == .opening)
  }

  @Test func hoverWorksAfterAnEscapeCloseWhileThePointerWasAway() {
    var machine = PanelMachine()
    _ = machine.handle(.hotkey)
    _ = machine.handle(away)
    _ = machine.handle(.escape)
    #expect(timer(machine.handle(onIcon))?.kind == .dwell)
  }

  @Test func theMachineRemembersTheIconStateSeenWhilePinned() {
    var machine = PanelMachine()
    _ = machine.handle(.hotkey)
    _ = machine.handle(onIcon)
    _ = machine.handle(.hotkey)
    #expect(machine.handle(onIcon).isEmpty)
    #expect(machine.phase == .hidden)
    _ = machine.handle(away)
    #expect(timer(machine.handle(onIcon)) != nil)
  }

  @Test func aHoverOpenedPanelNeverRequestsKeyFocus() {
    var machine = PanelMachine()
    var effects = machine.handle(onIcon)
    let dwell = timer(effects)!
    effects += machine.handle(.timer(dwell))
    effects += machine.handle(onPanel)
    effects += machine.handle(away)
    #expect(!effects.contains(.show(pinned: true)))
    #expect(effects.contains(.show(pinned: false)))
  }

  @Test func onlyClickAndHotkeyRequestKeyFocus() {
    var click = PanelMachine()
    #expect(click.handle(.iconClick) == [.show(pinned: true)])
    var hotkey = PanelMachine()
    #expect(hotkey.handle(.hotkey) == [.show(pinned: true)])
  }
}
