// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeerJetty",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "PeerJetty", targets: ["PeerJetty"]),
               .executable(name: "PeerHarness", targets: ["PeerHarness"])],
    targets: [.target(name: "PeerCore", resources: [.process("Resources")]),
              .executableTarget(name: "PeerJetty", dependencies: ["PeerCore"]),
              .executableTarget(name: "PeerHarness", dependencies: ["PeerCore"]),
              .executableTarget(name: "PeerTests", dependencies: ["PeerCore"], path: "Tests/PeerCoreTests")]
)
