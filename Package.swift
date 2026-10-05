// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenOnMini",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "OpenOnMini", targets: ["OpenOnMini"]),
               .executable(name: "PeerHarness", targets: ["PeerHarness"])],
    targets: [.target(name: "PeerCore"),
              .executableTarget(name: "OpenOnMini", dependencies: ["PeerCore"]),
              .executableTarget(name: "PeerHarness", dependencies: ["PeerCore"]),
              .executableTarget(name: "PeerTests", dependencies: ["PeerCore"], path: "Tests/PeerCoreTests")]
)
