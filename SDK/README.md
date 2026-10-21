# A-Kit SDK

把 macOS 菜单栏工具接进 [A-Kit](https://github.com/BacheLor11/A-Kit) 的单文件 SDK。

- `AKitStatusKit.swift` —— 唯一需要的文件，零第三方依赖，只 `import Foundation`
- `akit.json` —— 工具自描述模板，放在你仓库根目录，A-Kit 就能识别并自动更新
- `Example/IntegratingApp.swift` —— 一个完整的最小示例（NSStatusItem + SDK）

完整文档：[docs/SDK.md](../docs/SDK.md)

```swift
import AKitStatusKit

AKHubClient.shared.onConnectionChange = { connected in
    statusItem.isVisible = !connected      // 接管时收起自己的图标
}
AKHubClient.shared.onInvoke = { id in handle(id) }
AKHubClient.shared.start(info: AKToolInfo(
    bundleId: Bundle.main.bundleIdentifier ?? "",
    name: "MyTool", version: "1.0.0",
    menu: [AKMenuItem(id: "toggle", title: "开始", kind: .toggle)]))
```

核心约定：**连不上 Hub 就什么都不做**。没装 A-Kit 的用户行为与接入前完全一致。
