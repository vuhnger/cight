import Foundation

public enum Feedback {
  public static let address = "victor.uhnger@gmail.com"

  public static func url(appVersion: String, build: String, system: OperatingSystemVersion) -> URL {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = address
    components.queryItems = [
      URLQueryItem(name: "subject", value: "Peek feedback"),
      URLQueryItem(
        name: "body",
        value:
          "\n\nPeek \(appVersion) (\(build))\nmacOS \(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
      ),
    ]
    return components.url!
  }
}
