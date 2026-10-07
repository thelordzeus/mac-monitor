// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MacMonitor",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "MacMonitor", targets: ["MacMonitor"])],
  targets: [
    .target(name: "BlitzCleanIntegration", path: "ThirdParty/BlitzClean/Sources"),
    .target(
      name: "SystemBridge", path: "Sources/SystemBridge", publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("IOKit"), .linkedFramework("CoreAudio"), .linkedFramework("Foundation"),
      ]),
    .executableTarget(
      name: "MacMonitor", dependencies: ["SystemBridge", "BlitzCleanIntegration"], path: "Sources/MacMonitor",
      linkerSettings: [
        .linkedFramework("IOBluetooth"), .linkedFramework("Metal"), .linkedLibrary("sqlite3"),
      ]),
    .testTarget(name: "BlitzCleanIntegrationTests", dependencies: ["BlitzCleanIntegration"]),
  ]
)
