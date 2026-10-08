// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "MacMonitor",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "MacMonitor", targets: ["MacMonitor"])],
  dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
  ],
  targets: [
    .target(name: "PulseCore"),
    .target(name: "CleanupCore", path: "ThirdParty/Cleanup/Sources"),
    .target(
      name: "SystemBridge", path: "Sources/SystemBridge", publicHeadersPath: "include",
      linkerSettings: [
        .linkedFramework("IOKit"), .linkedFramework("CoreAudio"), .linkedFramework("Foundation"),
      ]),
    .executableTarget(
      name: "MacMonitor",
      dependencies: ["SystemBridge", "CleanupCore", "PulseCore", .product(name: "Sparkle", package: "Sparkle")],
      path: "Sources/MacMonitor",
      linkerSettings: [
        .linkedFramework("IOBluetooth"), .linkedFramework("Metal"), .linkedLibrary("sqlite3"),
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
      ]),
    .testTarget(name: "CleanupCoreTests", dependencies: ["CleanupCore"]),
    .testTarget(name: "PulseCoreTests", dependencies: ["PulseCore"]),
  ]
)
