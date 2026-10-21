// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "A-Kit",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "AKitHub", targets: ["AKitHub"]),
        .executable(name: "akit", targets: ["AKitCLI"]),
        .library(name: "AKitCore", targets: ["AKitCore"]),
        .library(name: "AKitStatusKit", targets: ["AKitStatusKit"]),
        // 注意：DemoTool 不出现在 products 里 —— 它是协议自测用的夹具，
        // 不是这个项目要分发的「工具」。真正的工具各自在自己的仓库。
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
