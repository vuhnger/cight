import AppKit
import CightCore
import Observation
import UserNotifications

@MainActor
@Observable
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
  private(set) var authorization = UNAuthorizationStatus.notDetermined

  var settings: NotificationSettings {
    didSet {
      settings.save(to: defaults)
      if settings.failed || settings.fixed || settings.started {
        Task { await requestAuthorizationIfNeeded() }
      }
    }
  }

  private let defaults: UserDefaults
  private let center = UNUserNotificationCenter.current()
  private var signOutGate = SignOutGate()

  init(defaults: UserDefaults) {
    self.defaults = defaults
    settings = NotificationSettings.load(from: defaults)
    super.init()
    center.delegate = self
    Task { await refreshAuthorization() }
  }

  func refreshAuthorization() async {
    authorization = await center.notificationSettings().authorizationStatus
  }

  func deliver(_ events: [RunEvent]) {
    for event in events {
      if let content = NotificationContent.make(for: event, settings: settings) {
        post(content)
      }
    }
  }

  func observe(signedOut: Bool) {
    if signOutGate.shouldNotify(signedOut: signedOut) {
      post(.signedOut)
    }
  }

  private func requestAuthorizationIfNeeded() async {
    await refreshAuthorization()
    guard authorization == .notDetermined else { return }
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
    await refreshAuthorization()
  }

  private func post(_ content: NotificationContent) {
    Task {
      await requestAuthorizationIfNeeded()
      guard authorization == .authorized || authorization == .provisional else { return }
      let message = UNMutableNotificationContent()
      message.title = content.title
      message.body = content.body
      message.sound = .default
      if let url = content.url {
        message.userInfo = ["url": url.absoluteString]
      }
      try? await center.add(
        UNNotificationRequest(identifier: content.identifier, content: message, trigger: nil))
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let address = response.notification.request.content.userInfo["url"] as? String
    guard let url = address.flatMap(URL.init(string:)) else { return }
    await MainActor.run { _ = NSWorkspace.shared.open(url) }
  }
}
