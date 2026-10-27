import Foundation

public enum LaunchAgentPlist {
  public static let label = "com.vuhnger.cight"
  public static let argument = "--launch-agent"

  public static func render(program: String) -> Data {
    let plist: [String: Any] = [
      "Label": label,
      "ProgramArguments": [program, argument],
      "RunAtLoad": true,
      "KeepAlive": ["SuccessfulExit": false],
      "ProcessType": "Interactive",
      "AbandonProcessGroup": true,
    ]
    return (try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
      ?? Data()
  }

  public static func program(in data: Data) -> String? {
    guard
      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    else { return nil }
    return (plist["ProgramArguments"] as? [String])?.first
  }
}

public enum StartupPlan: Sendable, Equatable {
  case run
  case yield
  case waitForOthers

  public static func decide(me: Int32, others: [Int32], byLaunchd: Bool) -> StartupPlan {
    if byLaunchd { return others.isEmpty ? .run : .waitForOthers }
    return others.contains { $0 < me } ? .yield : .run
  }
}
