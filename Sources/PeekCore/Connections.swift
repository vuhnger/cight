public struct ConnectionAccount: Sendable, Equatable {
  public let host: String
  public let login: String?
  public let signedOut: Bool

  public init(host: String, login: String?, signedOut: Bool) {
    self.host = host
    self.login = login
    self.signedOut = signedOut
  }
}

public struct ConnectionRow: Sendable, Equatable, Identifiable {
  public let isSignedIn: Bool
  public let text: String

  public var id: String { text }

  public init(isSignedIn: Bool, text: String) {
    self.isSignedIn = isSignedIn
    self.text = text
  }
}

public enum Connections {
  public static func rows(github: ConnectionAccount, gitLab: [ConnectionAccount])
    -> [ConnectionRow]
  {
    var rows: [ConnectionRow] = []
    if let row = row(github, name: "GitHub", command: "gh") { rows.append(row) }
    if gitLab.isEmpty {
      rows.append(
        ConnectionRow(
          isSignedIn: false,
          text: "GitLab is off. Install glab and run glab auth login in Terminal."))
    }
    rows += gitLab.compactMap { row($0, name: $0.host, command: "glab") }
    return rows
  }

  private static func row(_ account: ConnectionAccount, name: String, command: String)
    -> ConnectionRow?
  {
    if account.signedOut {
      return ConnectionRow(
        isSignedIn: false, text: "Signed out of \(name). Run \(command) auth login in Terminal.")
    }
    return account.login.map {
      ConnectionRow(isSignedIn: true, text: "Signed in to \(name) as \($0).")
    }
  }
}
