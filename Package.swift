// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Cight",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "Cight", targets: ["Cight"])],
  targets: [
    .target(name: "CightCore"),
    .executableTarget(name: "Cight", dependencies: ["CightCore"]),
    .testTarget(
      name: "CightCoreTests", dependencies: ["CightCore"], resources: [.copy("Fixtures")]),
  ],
  swiftLanguageModes: [.v6]
)
