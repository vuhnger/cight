import Foundation

enum CLIRunner {
  static func read(
    paths: [String], arguments: [String], timeout: TimeInterval
  ) async -> String? {
    guard let path = paths.first(where: FileManager.default.isExecutableFile) else { return nil }
    return await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: run(path: path, arguments: arguments, timeout: timeout))
      }
    }
  }

  private static func run(path: String, arguments: [String], timeout: TimeInterval) -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
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
    let text = String(decoding: data, as: UTF8.self).trimmingCharacters(
      in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }
}
