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

  public init() {}

  public mutating func handle(_ input: PanelInput) -> [PanelEffect] {
    []
  }
}
