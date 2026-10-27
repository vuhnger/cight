// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Cight",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "Cight", targets: ["Cight"])],
  dependencies: [
    .package(
      url: "https://github.com/sparkle-project/Sparkle",
      exact: "2.10.1"
    )
  ],
  targets: [
    .target(name: "CightCore"),
    .executableTarget(
      name: "Cight",
      dependencies: ["CightCore", .product(name: "Sparkle", package: "Sparkle")]),
    .testTarget(
      name: "CightCoreTests", dependencies: ["CightCore"], resources: [.copy("Fixtures")]),
    .testTarget(name: "CightTests", dependencies: ["Cight", "CightCore"]),
  ],
  swiftLanguageModes: [.v6]
)
