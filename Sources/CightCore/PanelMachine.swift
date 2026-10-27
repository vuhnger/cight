import Foundation

public enum PanelPhase: Sendable, Equatable {
  case hidden
  case opening
  case hoverOpen
  case closing
  case pinned
}

public struct PanelTimer: Sendable, Equatable {
  public enum Kind: Sendable, Equatable {
    case dwell
    case grace
  }

  public let kind: Kind
  public let delay: TimeInterval
  let token: Int
}

public enum PanelInput: Sendable, Equatable {
  case pointer(overIcon: Bool, overPanel: Bool)
  case iconClick
  case hotkey
  case escape
  case outsideClick
  case dismiss
  case timer(PanelTimer)
}

public enum PanelEffect: Sendable, Equatable {
  case show(pinned: Bool)
  case hide
  case schedule(PanelTimer)
  case cancelTimer
}

public struct PanelMachine: Sendable {
  public static let dwell: TimeInterval = 0.14
  public static let grace: TimeInterval = 0.3

  public private(set) var phase = PanelPhase.hidden
  private var token = 0
  private var armed = true

  public init() {}

  public mutating func handle(_ input: PanelInput) -> [PanelEffect] {
    switch input {
    case .pointer(let overIcon, let overPanel):
      return pointer(overIcon: overIcon, overPanel: overPanel)
    case .iconClick:
      return phase == .pinned ? close() : pin()
    case .hotkey:
      switch phase {
      case .hidden, .opening: return pin()
      case .hoverOpen, .closing, .pinned: return close()
      }
    case .escape, .outsideClick, .dismiss:
      return phase == .hidden || phase == .opening ? [] : close()
    case .timer(let timer):
      return fire(timer)
    }
  }

  private mutating func pointer(overIcon: Bool, overPanel: Bool) -> [PanelEffect] {
    if !overIcon { armed = true }
    switch phase {
    case .hidden:
      guard overIcon, armed else { return [] }
      phase = .opening
      return [schedule(.dwell, after: Self.dwell)]
    case .opening:
      guard !overIcon else { return [] }
      phase = .hidden
      return cancel()
    case .hoverOpen:
      guard !overIcon, !overPanel else { return [] }
      phase = .closing
      return [schedule(.grace, after: Self.grace)]
    case .closing:
      guard overIcon || overPanel else { return [] }
      phase = .hoverOpen
      return cancel()
    case .pinned:
      return []
    }
  }

  private mutating func fire(_ timer: PanelTimer) -> [PanelEffect] {
    guard timer.token == token else { return [] }
    switch (timer.kind, phase) {
    case (.dwell, .opening):
      phase = .hoverOpen
      token += 1
      return [.show(pinned: false)]
    case (.grace, .closing):
      phase = .hidden
      token += 1
      return [.hide]
    default:
      return []
    }
  }

  private mutating func pin() -> [PanelEffect] {
    let hadTimer = phase == .opening || phase == .closing
    phase = .pinned
    token += 1
    return (hadTimer ? [.cancelTimer] : []) + [.show(pinned: true)]
  }

  private mutating func close() -> [PanelEffect] {
    let hadTimer = phase == .closing
    phase = .hidden
    armed = false
    token += 1
    return (hadTimer ? [.cancelTimer] : []) + [.hide]
  }

  private mutating func cancel() -> [PanelEffect] {
    token += 1
    return [.cancelTimer]
  }

  private mutating func schedule(_ kind: PanelTimer.Kind, after delay: TimeInterval)
    -> PanelEffect
  {
    token += 1
    return .schedule(PanelTimer(kind: kind, delay: delay, token: token))
  }
}
