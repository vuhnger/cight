// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Peek",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "Peek", targets: ["Peek"])],
  dependencies: [
    .package(
      url: "https://github.com/sparkle-project/Sparkle",
      exact: "2.10.1"
    )
  ],
  targets: [
    .target(name: "PeekCore"),
    .executableTarget(
      name: "Peek",
      dependencies: ["PeekCore", .product(name: "Sparkle", package: "Sparkle")]),
    .testTarget(
      name: "PeekCoreTests", dependencies: ["PeekCore"], resources: [.copy("Fixtures")]),
    .testTarget(name: "PeekTests", dependencies: ["Peek", "PeekCore"]),
  ],
  swiftLanguageModes: [.v6]
)
