import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let control = ShortcutModifiers(rawValue: 1)
  public static let option = ShortcutModifiers(rawValue: 2)
  public static let shift = ShortcutModifiers(rawValue: 4)
  public static let command = ShortcutModifiers(rawValue: 8)
}

public struct Shortcut: Codable, Equatable, Sendable {
  public static let key = "panelShortcut"
  public static let standard = Shortcut(
    keyCode: 5, modifiers: [.control, .option, .command], label: "G")

  public let keyCode: UInt32
  public let modifiers: ShortcutModifiers
  public let label: String

  public init(keyCode: UInt32, modifiers: ShortcutModifiers, label: String) {
    self.keyCode = keyCode
    self.modifiers = modifiers
    self.label = label
  }

  public init?(keyCode: UInt32, modifiers: ShortcutModifiers, characters: String?) {
    guard !modifiers.isDisjoint(with: [.command, .control, .option]),
      let label = Self.specialLabels[keyCode] ?? Self.printable(characters)
    else { return nil }
    self.init(keyCode: keyCode, modifiers: modifiers, label: label)
  }

  public var display: String {
    let names: [(ShortcutModifiers, String)] = [
      (.control, "Ctrl"), (.option, "Opt"), (.shift, "Shift"), (.command, "Cmd"),
    ]
    return (names.filter { modifiers.contains($0.0) }.map(\.1) + [label]).joined(separator: "+")
  }

  public static func load(from defaults: UserDefaults) -> Shortcut {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
      ?? standard
  }

  public func save(to defaults: UserDefaults) {
    defaults.set(try? JSONEncoder().encode(self), forKey: Self.key)
  }

  private static func printable(_ characters: String?) -> String? {
    guard let characters, characters.unicodeScalars.count == 1,
      let scalar = characters.unicodeScalars.first,
      !CharacterSet.controlCharacters.contains(scalar),
      !CharacterSet.whitespacesAndNewlines.contains(scalar),
      !(0xF700...0xF8FF).contains(scalar.value)
    else { return nil }
    return characters.uppercased()
  }

  private static let specialLabels: [UInt32: String] = [
    49: "Space", 48: "Tab", 36: "Return", 51: "Delete",
    123: "Left", 124: "Right", 125: "Down", 126: "Up",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
  ]
}
