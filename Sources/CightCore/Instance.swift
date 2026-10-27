import Darwin
import Foundation

public enum LockOutcome: Sendable, Equatable {
  case acquired
  case held
  case failed
}

public struct LockAttempt {
  public let outcome: LockOutcome
  public let lock: InstanceLock?
}

public final class InstanceLock: @unchecked Sendable {
  private static let pollInterval: useconds_t = 50_000

  private let mutex = NSLock()
  private var descriptor: Int32

  private init(descriptor: Int32) {
    self.descriptor = descriptor
  }

  deinit {
    release()
  }

  public static func acquire(at url: URL, timeout: TimeInterval = 0) -> LockAttempt {
    let directory = url.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { return LockAttempt(outcome: .failed, lock: nil) }
      if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
        return LockAttempt(outcome: .acquired, lock: InstanceLock(descriptor: descriptor))
      }
      let contended = errno == EWOULDBLOCK
      close(descriptor)
      guard contended else { return LockAttempt(outcome: .failed, lock: nil) }
      guard Date() < deadline else { return LockAttempt(outcome: .held, lock: nil) }
      usleep(pollInterval)
    }
  }

  public func release() {
    mutex.lock()
    defer { mutex.unlock() }
    guard descriptor >= 0 else { return }
    flock(descriptor, LOCK_UN)
    close(descriptor)
    descriptor = -1
  }
}

public enum StartupPlan: Sendable, Equatable {
  case run
  case waitForLock
  case kickstartThenExit
  case exitQuietly
  case exitFailure

  public static let waitTimeout: TimeInterval = 10

  public static func decide(
    lock: LockOutcome, startedByAgent: Bool, waitsForLock: Bool, agentEnabled: Bool
  ) -> StartupPlan {
    if lock == .failed { return .exitFailure }
    if startedByAgent || waitsForLock { return lock == .acquired ? .run : .waitForLock }
    if agentEnabled { return .kickstartThenExit }
    return lock == .acquired ? .run : .exitQuietly
  }
}

public struct AgentIdentity: Equatable, Sendable {
  public let version: String
  public let binaryHash: String

  private static let versionKey = "agentVersion"
  private static let hashKey = "agentBinaryHash"

  public init(version: String, binaryHash: String) {
    self.version = version
    self.binaryHash = binaryHash
  }

  public static func load(from defaults: UserDefaults) -> AgentIdentity? {
    guard let version = defaults.string(forKey: versionKey),
      let hash = defaults.string(forKey: hashKey)
    else { return nil }
    return AgentIdentity(version: version, binaryHash: hash)
  }

  public func save(to defaults: UserDefaults) {
    defaults.set(version, forKey: Self.versionKey)
    defaults.set(binaryHash, forKey: Self.hashKey)
  }
}

public enum ReregisterPolicy {
  public static func shouldReregister(
    agentEnabled: Bool, stored: AgentIdentity?, current: AgentIdentity
  ) -> Bool {
    agentEnabled && stored != current
  }
}
