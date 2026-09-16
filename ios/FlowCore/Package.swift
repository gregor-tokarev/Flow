// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FlowCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "FlowCore", targets: ["FlowCore"])],
    dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
    targets: [
        .target(name: "FlowCore", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "FlowCoreTests", dependencies: ["FlowCore", "ZIPFoundation"], resources: [.copy("Fixtures")])
    ]
)
