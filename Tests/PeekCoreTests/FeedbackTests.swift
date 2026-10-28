import Foundation
import Testing

@testable import PeekCore

struct FeedbackTests {
  private let version = OperatingSystemVersion(majorVersion: 26, minorVersion: 1, patchVersion: 2)

  private func url() -> URL {
    Feedback.url(appVersion: "1.2.3", build: "45", system: version)
  }

  private func value(_ name: String) -> String? {
    URLComponents(url: url(), resolvingAgainstBaseURL: false)?.queryItems?
      .first { $0.name == name }?.value
  }

  @Test func addressesTheMailToTheMaintainer() {
    #expect(url().scheme == "mailto")
    #expect(url().path == "victor.uhnger@gmail.com")
  }

  @Test func setsTheSubject() {
    #expect(value("subject") == "Peek feedback")
  }

  @Test func bodyHasTwoBlankLinesThenVersionAndSystem() {
    #expect(value("body") == "\n\nPeek 1.2.3 (45)\nmacOS 26.1.2")
  }

  @Test func percentEncodesSpacesParenthesesAndNewlines() {
    let raw = url().absoluteString
    #expect(raw.contains("subject=Peek%20feedback"))
    #expect(raw.contains("body=%0A%0APeek%201.2.3%20(45)%0AmacOS%2026.1.2"))
    #expect(!raw.contains(" "))
    #expect(!raw.contains("\n"))
  }
}
