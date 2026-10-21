// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "A-Kit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AKitHub", targets: ["AKitHub"]),
        .executable(name: "akit", targets: ["AKitCLI"]),
        .executable(name: "DemoTool", targets: ["AKitDemoTool"]),
        .library(name: "AKitCore", targets: ["AKitCore"]),
        .library(name: "AKitStatusKit", targets: ["AKitStatusKit"]),
    ],
    targets: [
        .target(name: "AKitStatusKit", path: "Sources/AKitStatusKit"),
        .target(name: "AKitCore", path: "Sources/AKitCore"),
        .executableTarget(
            name: "AKitHub",
            dependencies: ["AKitCore", "AKitStatusKit"],
            path: "Sources/AKitHub"
        ),
        .executableTarget(
            name: "AKitCLI",
            dependencies: ["AKitCore"],
            path: "Sources/AKitCLI"
        ),
        .executableTarget(
            name: "AKitDemoTool",
            dependencies: ["AKitStatusKit"],
            path: "Sources/AKitDemoTool"
        ),
    ],
    swiftLanguageModes: [.v5]
)
