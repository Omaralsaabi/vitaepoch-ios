// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VitaEpochCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "VitaEpochCore", targets: ["VitaEpochCore"])],
    targets: [.target(name: "VitaEpochCore"), .testTarget(name: "VitaEpochCoreTests", dependencies: ["VitaEpochCore"], resources: [.copy("Fixtures")])]
)
