import Foundation

public enum GlabCLI {
  public static let defaultPaths = ["/opt/homebrew/bin/glab", "/usr/local/bin/glab"]

  public static func token(
    host: String, paths: [String] = defaultPaths, timeout: TimeInterval = 5
  ) async -> String? {
    guard isValidHost(host) else { return nil }
    return await CLIRunner.read(
      paths: paths, arguments: ["config", "get", "token", "--host", host], timeout: timeout)
  }

  public static func hosts(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    paths: [String] = defaultPaths
  ) -> [String] {
    guard paths.contains(where: FileManager.default.isExecutableFile) else { return [] }
    let text = configFiles(environment: environment, home: home).lazy
      .compactMap { try? String(contentsOf: $0, encoding: .utf8) }.first
    return text.map(parseHosts) ?? []
  }

  static func configFiles(environment: [String: String], home: URL) -> [URL] {
    var files: [URL] = []
    if let dir = environment["GLAB_CONFIG_DIR"], !dir.isEmpty {
      files.append(URL(fileURLWithPath: dir).appending(path: "config.yml"))
    }
    files.append(home.appending(path: ".config/glab-cli/config.yml"))
    files.append(home.appending(path: "Library/Application Support/glab-cli/config.yml"))
    return files
  }

  static func parseHosts(_ yaml: String) -> [String] {
    var hosts: [String] = []
    var inHosts = false
    var hostIndent: Int?
    for line in yaml.split(separator: "\n", omittingEmptySubsequences: true) {
      let indent = line.prefix { $0 == " " }.count
      let content = line.dropFirst(indent).trimmingCharacters(in: .whitespaces)
      if content.isEmpty || content.hasPrefix("#") { continue }
      if indent == 0 {
        inHosts = content == "hosts:"
        hostIndent = nil
        continue
      }
      guard inHosts, content.hasSuffix(":") else { continue }
      hostIndent = hostIndent ?? indent
      guard indent == hostIndent else { continue }
      let name = content.dropLast().trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
      if isValidHost(name), !hosts.contains(name) { hosts.append(name) }
    }
    return hosts
  }

  static func isValidHost(_ value: String) -> Bool {
    let allowed = CharacterSet(
      charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:")
    return !value.isEmpty && value.count <= 253 && value.unicodeScalars.allSatisfy(allowed.contains)
      && !value.hasPrefix("-") && !value.hasPrefix(".")
  }
}
