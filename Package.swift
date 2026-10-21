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
        // 插件契约：插件开发者只依赖这一个（只有 @objc 协议，不含实现）
        .library(name: "AKitPluginKit", targets: ["AKitPluginKit"]),
        // 宿主专用：dlopen / 崩溃哨兵 / 实例锁。插件**不要**依赖它——
        // 插件静态链接这份实现后，同一个类会在进程里出现两份，ObjC runtime 会报
        // "Class ... is implemented in both ..."，进而引发类型转换失败。
        .library(name: "AKitHostKit", targets: ["AKitHostKit"]),
        // 示例插件：给接入文档配的可编译样例，也是宿主加载链路的自测夹具。
        // 不随 A-Kit 分发，装的时候脚本会把它组装成 .akitplugin。
        .library(name: "AKitSamplePlugin", type: .dynamic, targets: ["AKitSamplePlugin"]),
        // 注意：DemoTool 不出现在 products 里 —— 它是协议自测用的夹具，
        // 不是这个项目要分发的「工具」。真正的工具各自在自己的仓库。
    ],
    targets: [
        .target(name: "AKitStatusKit", path: "Sources/AKitStatusKit"),
        .target(name: "AKitPluginKit", path: "Sources/AKitPluginKit"),
        .target(name: "AKitHostKit", dependencies: ["AKitPluginKit"], path: "Sources/AKitHostKit"),
        .target(name: "AKitCore", path: "Sources/AKitCore"),
        .target(
            name: "AKitSamplePlugin",
            dependencies: ["AKitPluginKit"],
            path: "Examples/SamplePlugin"
        ),
        .executableTarget(
            name: "AKitHub",
            dependencies: ["AKitCore", "AKitStatusKit", "AKitPluginKit", "AKitHostKit"],
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
