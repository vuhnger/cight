import Darwin
import Foundation

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

  public static func acquire(at url: URL, timeout: TimeInterval = 0) -> InstanceLock? {
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let deadline = Date().addingTimeInterval(timeout)
    while true {
      let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
      guard descriptor >= 0 else { return nil }
      if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
        return InstanceLock(descriptor: descriptor)
      }
      close(descriptor)
      guard Date() < deadline else { return nil }
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
  case takeOver(askHolderToQuit: Bool)
  case exit

  public static func decide(
    lockAcquired: Bool, startedByAgent: Bool, waitsForLock: Bool
  ) -> StartupPlan {
    if lockAcquired { return .run }
    if startedByAgent { return .takeOver(askHolderToQuit: true) }
    if waitsForLock { return .takeOver(askHolderToQuit: false) }
    return .exit
  }
}

public enum HandoverPolicy {
  public static let quitRequest = "com.vuhnger.cight.quit-for-agent"
  public static let takeOverTimeout: TimeInterval = 10

  public static func holderShouldYield(startedByAgent: Bool) -> Bool {
    !startedByAgent
  }
}
