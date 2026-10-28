import Foundation
import Testing

@testable import CightCore

struct ShortcutTests {
  @Test func defaultReadsInPlainWords() {
    #expect(Shortcut.standard.display == "Ctrl+Opt+Cmd+G")
  }

  @Test func modifiersFollowCtrlOptShiftCmdOrder() {
    let shortcut = Shortcut(
      keyCode: 5, modifiers: [.command, .shift, .option, .control], label: "G")
    #expect(shortcut.display == "Ctrl+Opt+Shift+Cmd+G")
  }

  @Test func specialKeyUsesItsName() {
    let shortcut = Shortcut(keyCode: 49, modifiers: [.command], characters: " ")
    #expect(shortcut?.display == "Cmd+Space")
  }

  @Test func functionKeyUsesItsName() {
    let shortcut = Shortcut(keyCode: 111, modifiers: [.control], characters: "\u{F70F}")
    #expect(shortcut?.display == "Ctrl+F12")
  }

  @Test func printableKeyIsUppercased() {
    #expect(Shortcut(keyCode: 0, modifiers: [.option], characters: "a")?.label == "A")
  }

  @Test func needsCommandControlOrOption() {
    #expect(Shortcut(keyCode: 0, modifiers: [], characters: "a") == nil)
    #expect(Shortcut(keyCode: 0, modifiers: [.shift], characters: "a") == nil)
    #expect(Shortcut(keyCode: 0, modifiers: [.shift, .command], characters: "a") != nil)
  }

  @Test func rejectsKeysWithoutAPrintableCharacter() {
    #expect(Shortcut(keyCode: 117, modifiers: [.command], characters: "\u{F728}") == nil)
    #expect(Shortcut(keyCode: 0, modifiers: [.command], characters: nil) == nil)
  }

  @Test func roundTripsThroughDefaults() throws {
    let name = "ShortcutTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    #expect(Shortcut.load(from: defaults) == .standard)
    let custom = Shortcut(keyCode: 40, modifiers: [.command, .shift], label: "K")
    custom.save(to: defaults)
    #expect(Shortcut.load(from: defaults) == custom)
  }
}
