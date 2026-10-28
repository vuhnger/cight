import PeekCore
import SwiftUI

struct SettingsView: View {
  var notifier: Notifier
  var updates: UpdateChecker
  var launchAtLogin: LaunchAtLogin
  var recorder: ShortcutRecorder
  var monitor: Monitor

  var body: some View {
    GeneralPane(
      notifier: notifier, updates: updates, launchAtLogin: launchAtLogin, recorder: recorder,
      monitor: monitor
    )
    .padding(20)
    .frame(width: 520, alignment: .top)
  }
}

private struct GeneralPane: View {
  @Bindable var notifier: Notifier
  var updates: UpdateChecker
  var launchAtLogin: LaunchAtLogin
  var recorder: ShortcutRecorder
  var monitor: Monitor
  @AppStorage(BuiltInRuns.key) private var showBuiltIn = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: Metrics.settingsInnerSpacing) {
        ForEach(monitor.connections) { row in
          HStack(alignment: .firstTextBaseline, spacing: Metrics.glyphGap) {
            StateGlyph(kind: row.isSignedIn ? .passed : .signedOut, size: Metrics.headerGlyph)
            Text(row.text)
          }
        }
      }

      Divider()

      Toggle(
        "Launch at login",
        isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.set($0) })
      )
      .disabled(launchAtLogin.busy)
      if let error = launchAtLogin.error {
        Text(error).foregroundStyle(.orange).font(.callout)
      }
      Toggle("Show GitHub's built-in runs, like Dependabot and CodeQL", isOn: $showBuiltIn)

      Divider()

      Toggle("Notify when a run fails", isOn: $notifier.settings.failed)
      Toggle("Notify when a failing run is fixed", isOn: $notifier.settings.fixed)
      Toggle("Notify when a run starts", isOn: $notifier.settings.started)
      Toggle(
        "Notify when a run passes on a pull request or merge request",
        isOn: $notifier.settings.passed)

      Divider()

      VStack(alignment: .leading, spacing: Metrics.settingsInnerSpacing) {
        HStack(spacing: Metrics.settingsInnerSpacing) {
          Text("Show or hide the panel with").foregroundStyle(.secondary)
          Button(recorder.recording ? "Type a shortcut" : recorder.shortcut.display) {
            recorder.start()
          }
          .controlSize(.small)
        }
        if let error = recorder.error {
          Text(error).foregroundStyle(.orange).font(.callout)
        }
      }

      Button("Check for updates") { updates.check() }
        .disabled(!updates.canCheck)

      Button("Quit Peek") { NSApplication.shared.terminate(nil) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
