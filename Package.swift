// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VitaEpochCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "VitaEpochCore", targets: ["VitaEpochCore"]),
               .executable(name: "x6-sleep-analysis", targets: ["X6SleepAnalysis"])],
    targets: [.target(name: "VitaEpochCore"),
              .target(name: "X6Research", dependencies: ["VitaEpochCore"]),
              .executableTarget(name: "X6SleepAnalysis", dependencies: ["VitaEpochCore", "X6Research"]), .testTarget(name: "VitaEpochCoreTests", dependencies: ["VitaEpochCore", "X6Research"], resources: [.copy("Fixtures")])]
)
