import Foundation

enum RepoPath {
  private static let segmentCharacters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")

  static func isValidSegment(_ value: String) -> Bool {
    !value.isEmpty && value != "." && value != ".."
      && value.unicodeScalars.allSatisfy(segmentCharacters.contains)
  }
}
