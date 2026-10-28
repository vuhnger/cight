import Foundation

extension WorkflowRun {
  public var isBuiltIn: Bool { event == "dynamic" }
}

public enum BuiltInRuns {
  public static let key = "showBuiltInRuns"

  public static func isShown(in defaults: UserDefaults) -> Bool {
    defaults.bool(forKey: key)
  }

  public static func filter(_ runs: [WorkflowRun], shown: Bool) -> [WorkflowRun] {
    shown ? runs : runs.filter { !$0.isBuiltIn }
  }
}
