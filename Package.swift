// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PeerJetty",
    defaultLocalization: "en",
    platforms: [.macOS("15.0")],
    products: [.executable(name: "PeerJetty", targets: ["PeerJetty"]),
               .executable(name: "PeerHarness", targets: ["PeerHarness"])],
    dependencies: [.package(url:"https://github.com/sparkle-project/Sparkle", exact:"2.10.0")],
    targets: [.target(name: "PeerCore", resources: [.process("Resources")]),
              .executableTarget(name: "PeerJetty", dependencies: ["PeerCore", .product(name:"Sparkle",package:"Sparkle")]),
              .executableTarget(name: "PeerHarness", dependencies: ["PeerCore"]),
              .executableTarget(name: "PeerTests", dependencies: ["PeerCore"], path: "Tests/PeerCoreTests")]
)
