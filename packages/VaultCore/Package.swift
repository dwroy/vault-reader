// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VaultCore",
    platforms: [.iOS(.v18), .macOS(.v14)],
    products: [.library(name: "VaultCore", targets: ["VaultCore"])],
    targets: [.target(name: "VaultCore"), .testTarget(name: "VaultCoreTests", dependencies: ["VaultCore"])]
)
