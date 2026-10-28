import Foundation
import Testing

@testable import PeekCore

private func makeDirectory() -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private func makeScript(_ body: String, in directory: URL, name: String = "gh") -> String {
  let url = directory.appendingPathComponent(name)
  try! "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
  try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  return url.path
}

struct GhTokenReaderTests {
  private let directory = makeDirectory()

  @Test func returnsTheTrimmedTokenAndPassesTheExpectedArguments() async {
    let script = makeScript(
      """
      [ "$*" = "auth token --hostname github.com" ] || exit 2
      echo "  ghp_abc123  "
      """, in: directory)
    #expect(await GhTokenReader.read(paths: [script], timeout: 5) == "ghp_abc123")
  }

  @Test func returnsNilOnANonZeroExitEvenWithOutput() async {
    let script = makeScript("echo ghp_abc123\nexit 1", in: directory)
    #expect(await GhTokenReader.read(paths: [script], timeout: 5) == nil)
  }

  @Test func returnsNilOnEmptyOutput() async {
    let blank = makeScript("echo '   '", in: directory, name: "blank")
    let silent = makeScript("exit 0", in: directory, name: "silent")
    #expect(await GhTokenReader.read(paths: [blank], timeout: 5) == nil)
    #expect(await GhTokenReader.read(paths: [silent], timeout: 5) == nil)
  }

  @Test func returnsNilAndStopsWaitingWhenTheBinaryHangs() async {
    let script = makeScript("exec sleep 30", in: directory)
    let started = Date()
    #expect(await GhTokenReader.read(paths: [script], timeout: 0.3) == nil)
    #expect(Date().timeIntervalSince(started) < 5)
  }

  @Test func returnsNilWhenNoBinaryExists() async {
    let missing = directory.appendingPathComponent("absent").path
    #expect(await GhTokenReader.read(paths: [missing], timeout: 5) == nil)
  }

  @Test func usesTheFirstExistingCandidate() async {
    let missing = directory.appendingPathComponent("absent").path
    let first = makeScript("echo first", in: directory, name: "first")
    let second = makeScript("echo second", in: directory, name: "second")
    #expect(await GhTokenReader.read(paths: [missing, first, second], timeout: 5) == "first")
  }

  @Test func doesNotFallBackToAnotherBinaryWhenTheFirstFails() async {
    let failing = makeScript("exit 1", in: directory, name: "failing")
    let working = makeScript("echo ghp_abc123", in: directory, name: "working")
    #expect(await GhTokenReader.read(paths: [failing, working], timeout: 5) == nil)
  }
}
