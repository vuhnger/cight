import Foundation

public enum Formatting {
  public static func duration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    if total < 60 { return "\(total)s" }
    if total < 3600 { return "\(total / 60)m \(total % 60)s" }
    return "\(total / 3600)h \(total % 3600 / 60)m"
  }

  public static func relative(from date: Date, now: Date) -> String {
    let seconds = Int(now.timeIntervalSince(date))
    switch seconds {
    case ..<5: return "just now"
    case ..<60: return "\(seconds)s ago"
    case ..<3600: return "\(seconds / 60)m ago"
    case ..<86400: return "\(seconds / 3600)h ago"
    default: return "\(seconds / 86400)d ago"
    }
  }

  public static func remaining(_ secondsLeft: TimeInterval) -> String {
    switch secondsLeft {
    case ...(-60): return "+\(Int(-secondsLeft) / 60)m"
    case ..<60: return "<1m left"
    default: return "\(Int(secondsLeft) / 60)m left"
    }
  }

  public static func login(_ login: String) -> String {
    login.hasSuffix("[bot]") ? String(login.dropLast(5)) : login
  }
}
