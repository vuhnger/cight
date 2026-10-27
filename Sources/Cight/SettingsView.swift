import CightCore
import SwiftUI
import UserNotifications

struct SettingsView: View {
  var notifier: Notifier
  var updates: UpdateChecker
  var launchAtLogin: LaunchAtLogin

  var body: some View {
    GeneralPane(notifier: notifier, updates: updates, launchAtLogin: launchAtLogin)
      .padding(20)
      .frame(width: 520, alignment: .top)
  }
}

private struct GeneralPane: View {
  @Bindable var notifier: Notifier
  var updates: UpdateChecker
  var launchAtLogin: LaunchAtLogin

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle(
        "Launch at login",
        isOn: Binding(get: { launchAtLogin.isOn }, set: { launchAtLogin.set($0) })
      )
      .disabled(launchAtLogin.busy)
      if let error = launchAtLogin.error {
        Text(error).foregroundStyle(.orange).font(.callout)
      }

      Divider()

      Toggle("Notify when a run fails", isOn: $notifier.settings.failed)
      Toggle("Notify when a failing run is fixed", isOn: $notifier.settings.fixed)
      Toggle("Notify when a run starts", isOn: $notifier.settings.started)
      if notifier.authorization == .denied {
        Text("Notifications are turned off for Cight in System Settings.")
          .foregroundStyle(.orange).font(.callout)
      }

      Divider()

      Text("Show or hide the panel with Ctrl+Opt+Cmd+G.").foregroundStyle(.secondary)

      Button("Check for updates") { updates.check() }
        .disabled(!updates.canCheck)

      Button("Quit Cight") { NSApplication.shared.terminate(nil) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task { await notifier.refreshAuthorization() }
  }
}
