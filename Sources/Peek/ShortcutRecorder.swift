import AppKit
import Observation
import PeekCore

@MainActor
@Observable
final class ShortcutRecorder {
  private(set) var shortcut: Shortcut
  private(set) var recording = false
  private(set) var error: String?
  @ObservationIgnored private var monitor: Any?
  @ObservationIgnored private let suspend: () -> Void
  @ObservationIgnored private let resume: () -> Void
  @ObservationIgnored private let apply: (Shortcut) -> Bool

  init(
    shortcut: Shortcut, suspend: @escaping () -> Void, resume: @escaping () -> Void,
    apply: @escaping (Shortcut) -> Bool
  ) {
    self.shortcut = shortcut
    self.suspend = suspend
    self.resume = resume
    self.apply = apply
  }

  func start() {
    guard !recording else { return }
    recording = true
    suspend()
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      MainActor.assumeIsolated { self?.handle(event) }
      return nil
    }
  }

  func cancel() {
    guard recording else { return }
    stop()
    resume()
  }

  private func handle(_ event: NSEvent) {
    if event.keyCode == 53 {
      cancel()
      return
    }
    guard
      let candidate = Shortcut(
        keyCode: UInt32(event.keyCode), modifiers: Self.modifiers(of: event),
        characters: event.charactersIgnoringModifiers)
    else { return }
    stop()
    if apply(candidate) {
      shortcut = candidate
      error = nil
    } else {
      error = "Another app uses that shortcut."
    }
  }

  private func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = false
  }

  private static func modifiers(of event: NSEvent) -> ShortcutModifiers {
    var result: ShortcutModifiers = []
    let flags = event.modifierFlags
    if flags.contains(.control) { result.insert(.control) }
    if flags.contains(.option) { result.insert(.option) }
    if flags.contains(.shift) { result.insert(.shift) }
    if flags.contains(.command) { result.insert(.command) }
    return result
  }
}
