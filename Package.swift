// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Limitaur",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LimitaurCore", targets: ["LimitaurCore"]), .executable(name: "Limitaur", targets: ["Limitaur"])],
    targets: [
        .target(name: "LimitaurCore"),
        .executableTarget(name: "Limitaur", dependencies: ["LimitaurCore"]),
        .testTarget(name: "LimitaurCoreTests", dependencies: ["LimitaurCore"], exclude: ["Fixtures"]),
        .testTarget(name: "LimitaurUITests", dependencies: ["Limitaur", "LimitaurCore"])
    ]
)
