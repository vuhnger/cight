import CightCore
import SwiftUI
import UserNotifications

extension BranchFilter {
  fileprivate var title: String {
    switch self {
    case .defaultBranch: "Default branch"
    case .mine: "My branches and default"
    case .all: "All branches"
    }
  }
}

struct SettingsView: View {
  @Bindable var model: SettingsModel
  var notifier: Notifier
  var launchAtLogin: LaunchAtLogin

  var body: some View {
    VStack(spacing: 16) {
      Picker("", selection: $model.pane) {
        ForEach(SettingsModel.Pane.allCases, id: \.self) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 240)

      switch model.pane {
      case .repositories: RepositoriesPane(model: model)
      case .general: GeneralPane(notifier: notifier, launchAtLogin: launchAtLogin)
      }
    }
    .padding(20)
    .frame(width: 520, alignment: .top)
    .task { await model.loadRepos() }
  }
}

private struct RepositoriesPane: View {
  @Bindable var model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if model.watched.isEmpty {
        Text("Nothing is watched yet. Pick a repository below.")
          .foregroundStyle(.secondary)
      }
      VStack(spacing: 0) {
        ForEach(model.watched, id: \.fullName) { repo in
          HStack {
            Text(repo.fullName).lineLimit(1)
            Spacer()
            Picker("", selection: filterBinding(for: repo)) {
              ForEach([BranchFilter.defaultBranch, .mine, .all], id: \.self) {
                Text($0.title).tag($0)
              }
            }
            .labelsHidden()
            .frame(width: 190)
            Button("Remove") { model.remove(repo) }
          }
          .padding(.vertical, 6)
          Divider()
        }
      }

      Text("\(model.countText) watched")
        .foregroundStyle(.secondary).monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .trailing)

      TextField("Search your repositories or type owner/repo", text: $model.query)
        .textFieldStyle(.roundedBorder)
        .onSubmit { submitTyped() }

      if let message = model.addMessage {
        Text(message).foregroundStyle(.orange).font(.callout)
      }
      if let message = model.loadMessage {
        Text(message).foregroundStyle(.orange).font(.callout)
      } else if model.isLoading && model.allRepos.isEmpty {
        Text("Loading your repositories").foregroundStyle(.secondary).font(.callout)
      }

      List {
        if let typed = model.typedRepo {
          HStack {
            Text("\(typed.owner)/\(typed.name)")
            Spacer()
            Button(model.isAdding ? "Checking" : "Add") { submitTyped() }
              .disabled(model.isAdding)
          }
        }
        ForEach(model.results, id: \.id) { repo in
          HStack {
            Text(repo.fullName).lineLimit(1)
            Spacer()
            Button("Watch") { model.add(repo) }
          }
        }
      }
      .frame(height: 190)
    }
  }

  private func submitTyped() {
    guard model.typedRepo != nil, !model.isAdding else { return }
    Task { await model.addTyped() }
  }

  private func filterBinding(for repo: WatchedRepo) -> Binding<BranchFilter> {
    Binding(
      get: { model.watched.first { $0.fullName == repo.fullName }?.filter ?? repo.filter },
      set: { model.setFilter($0, for: repo) })
  }
}

extension WatchedRepo {
  fileprivate var fullName: String { "\(owner)/\(name)" }
}

private struct GeneralPane: View {
  @Bindable var notifier: Notifier
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

      Button("Quit Cight") { NSApplication.shared.terminate(nil) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .task { await notifier.refreshAuthorization() }
  }
}
