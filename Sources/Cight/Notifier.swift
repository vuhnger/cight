import AppKit
import CightCore
import Observation
import UserNotifications

@MainActor
protocol NotificationCentering: AnyObject {
  func authorizationStatus() async -> UNAuthorizationStatus
  func requestAuthorization() async
  func add(_ content: NotificationContent) async
}

@MainActor
final class SystemNotificationCenter: NSObject, NotificationCentering,
  UNUserNotificationCenterDelegate
{
  private let center: UNUserNotificationCenter

  static func make() -> SystemNotificationCenter? {
    guard Bundle.main.bundleIdentifier != nil else { return nil }
    return SystemNotificationCenter()
  }

  private override init() {
    center = UNUserNotificationCenter.current()
    super.init()
    center.delegate = self
  }

  func authorizationStatus() async -> UNAuthorizationStatus {
    await center.notificationSettings().authorizationStatus
  }

  func requestAuthorization() async {
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
  }

  func add(_ content: NotificationContent) async {
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

@MainActor
@Observable
final class Notifier {
  private(set) var authorization = UNAuthorizationStatus.notDetermined

  var settings: NotificationSettings {
    didSet {
      settings.save(to: defaults)
      if settings.failed || settings.fixed || settings.started {
        Task { await requestAuthorizationIfNeeded() }
      }
    }
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let center: (any NotificationCentering)?
  @ObservationIgnored private var signOutGate: SignOutGate

  init(defaults: UserDefaults, center: (any NotificationCentering)?) {
    self.defaults = defaults
    self.center = center
    signOutGate = SignOutGate(defaults: defaults)
    settings = NotificationSettings.load(from: defaults)
    Task { await refreshAuthorization() }
  }

  var isAllowed: Bool {
    authorization == .authorized || authorization == .provisional
  }

  func refreshAuthorization() async {
    guard let center else { return }
    authorization = await center.authorizationStatus()
  }

  func deliver(_ events: [RunEvent]) async {
    for event in events {
      if let content = NotificationContent.make(for: event, settings: settings) {
        _ = await post(content, mayPrompt: true)
      }
    }
  }

  func observe(_ state: SessionState) async {
    if signOutGate.shouldNotify(state), await post(.signedOut, mayPrompt: false) {
      signOutGate.didPost()
    }
  }

  private func requestAuthorizationIfNeeded() async {
    guard let center else { return }
    await refreshAuthorization()
    guard authorization == .notDetermined else { return }
    await center.requestAuthorization()
    await refreshAuthorization()
  }

  private func post(_ content: NotificationContent, mayPrompt: Bool) async -> Bool {
    guard let center else { return false }
    if mayPrompt {
      await requestAuthorizationIfNeeded()
    } else {
      await refreshAuthorization()
    }
    guard isAllowed else { return false }
    await center.add(content)
    return true
  }
}
