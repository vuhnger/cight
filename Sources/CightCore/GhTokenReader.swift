import Foundation

public enum GhTokenReader {
  public static let defaultPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

  public static func read(
    paths: [String] = defaultPaths, timeout: TimeInterval = 5
  ) async -> String? {
    guard let path = paths.first(where: FileManager.default.isExecutableFile) else { return nil }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: run(path: path, timeout: timeout))
      }
    }
  }

  private static func run(path: String, timeout: TimeInterval) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = ["auth", "token", "--hostname", "github.com"]
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    let exited = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in exited.signal() }
    guard (try? process.run()) != nil else { return nil }
    guard exited.wait(timeout: .now() + timeout) == .success else {
      process.terminate()
      if exited.wait(timeout: .now() + 1) == .timedOut { kill(process.processIdentifier, SIGKILL) }
      return nil
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard process.terminationStatus == 0 else { return nil }
    let token = String(decoding: data, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return token.isEmpty ? nil : token
  }
}
