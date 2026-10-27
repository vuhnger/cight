import ImageIO
import SwiftUI

enum AvatarCache {
  private static let host = "avatars.githubusercontent.com"
  private static let pixels = 48
  private static let countLimit = 200
  nonisolated(unsafe) private static let images: NSCache<NSURL, CGImage> = {
    let cache = NSCache<NSURL, CGImage>()
    cache.countLimit = countLimit
    return cache
  }()
  private static let session = URLSession(configuration: .ephemeral)

  static func url(_ string: String?) -> URL? {
    guard let string, let url = URL(string: string), url.scheme == "https", url.host == host
    else { return nil }
    return url
  }

  static func cached(_ url: URL) -> CGImage? {
    images.object(forKey: url as NSURL)
  }

  static func load(_ url: URL) async -> CGImage? {
    if let image = cached(url) { return image }
    return await AvatarLoader.shared.image(for: url)
  }

  fileprivate static func download(_ url: URL) async -> CGImage? {
    guard let (data, response) = try? await session.data(from: url),
      (response as? HTTPURLResponse)?.statusCode == 200,
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: pixels,
        ] as CFDictionary)
    else { return nil }
    images.setObject(image, forKey: url as NSURL)
    return image
  }
}

actor AvatarLoader {
  static let shared = AvatarLoader()
  private static let retryAfter: TimeInterval = 300

  private var inFlight: [URL: Task<CGImage?, Never>] = [:]
  private var failed: [URL: Date] = [:]

  func image(for url: URL) async -> CGImage? {
    if let image = AvatarCache.cached(url) { return image }
    if let failedAt = failed[url], Date().timeIntervalSince(failedAt) < Self.retryAfter {
      return nil
    }
    if let running = inFlight[url] { return await running.value }
    let task = Task { await AvatarCache.download(url) }
    inFlight[url] = task
    let image = await task.value
    inFlight[url] = nil
    failed[url] = image == nil ? Date() : nil
    return image
  }
}

struct AvatarView: View {
  let url: URL?
  let login: String
  let size: CGFloat
  @State private var image: CGImage?

  init(url: URL?, login: String, size: CGFloat = 16) {
    self.url = url
    self.login = login
    self.size = size
    _image = State(initialValue: url.flatMap(AvatarCache.cached))
  }

  var body: some View {
    ZStack {
      Circle().fill(.gray.gradient)
      Text(login.prefix(1).uppercased())
        .font(.system(size: size * 0.55, weight: .semibold))
        .foregroundStyle(.white)
      if let image {
        Image(decorative: image, scale: 3).resizable().clipShape(Circle())
      }
    }
    .frame(width: size, height: size)
    .task(id: url) {
      guard image == nil, let url else { return }
      image = await AvatarCache.load(url)
    }
  }
}
