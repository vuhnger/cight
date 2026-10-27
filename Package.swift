// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "Cight",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "Cight", targets: ["Cight"])],
  targets: [.executableTarget(name: "Cight")],
  swiftLanguageModes: [.v6]
)
