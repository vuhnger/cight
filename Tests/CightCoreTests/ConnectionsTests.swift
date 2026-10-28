import Testing

@testable import CightCore

struct ConnectionsTests {
  private let signedIn = ConnectionAccount(host: "github.com", login: "vuhnger", signedOut: false)
  private let signedOut = ConnectionAccount(host: "github.com", login: nil, signedOut: true)

  @Test func githubSignedIn() {
    let rows = Connections.rows(github: signedIn, gitLab: [])
    #expect(rows.first == ConnectionRow(isSignedIn: true, text: "Signed in to GitHub as vuhnger."))
  }

  @Test func githubSignedOut() {
    let rows = Connections.rows(github: signedOut, gitLab: [])
    #expect(
      rows.first
        == ConnectionRow(
          isSignedIn: false, text: "Signed out of GitHub. Run gh auth login in Terminal."))
  }

  @Test func githubUnknownHasNoRow() {
    let unknown = ConnectionAccount(host: "github.com", login: nil, signedOut: false)
    let rows = Connections.rows(github: unknown, gitLab: [])
    #expect(rows.count == 1)
    #expect(rows.first?.text.hasPrefix("GitLab") == true)
  }

  @Test func gitLabHostSignedIn() {
    let host = ConnectionAccount(host: "gitlab.com", login: "victor", signedOut: false)
    let rows = Connections.rows(github: signedIn, gitLab: [host])
    #expect(
      rows.map(\.text) == [
        "Signed in to GitHub as vuhnger.", "Signed in to gitlab.com as victor.",
      ])
    #expect(rows.map(\.isSignedIn) == [true, true])
  }

  @Test func gitLabHostSignedOut() {
    let host = ConnectionAccount(host: "git.example.com", login: nil, signedOut: true)
    let rows = Connections.rows(github: signedIn, gitLab: [host])
    #expect(
      rows.last
        == ConnectionRow(
          isSignedIn: false,
          text: "Signed out of git.example.com. Run glab auth login in Terminal."))
  }

  @Test func gitLabOffWhenNoHosts() {
    let rows = Connections.rows(github: signedIn, gitLab: [])
    #expect(
      rows.last
        == ConnectionRow(
          isSignedIn: false,
          text: "GitLab is off. Install glab and run glab auth login in Terminal."))
  }

  @Test func hostWithoutLoginOrSignOutIsHidden() {
    let host = ConnectionAccount(host: "gitlab.com", login: nil, signedOut: false)
    #expect(Connections.rows(github: signedIn, gitLab: [host]).count == 1)
  }
}
