# A-Kit SDK

把 macOS 菜单栏工具接进 [A-Kit](https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS) 的单文件 SDK。

**这个 SDK 是给「另一个仓库」用的。** A-Kit 主仓库只放引擎，你的工具留在你自己的仓库里，
把下面这个文件复制过去、加一个 `akit.json`、发一个 Release —— 别人就能在 A-Kit 里粘链接装上你的工具。

- `AKitStatusKit.swift` —— 唯一需要的文件，零第三方依赖，只 `import Foundation`
- `akit.json` —— 工具自描述模板，放在你仓库根目录，A-Kit 就能识别并自动更新
- `Example/IntegratingApp.swift` —— 一个完整的最小示例（NSStatusItem + SDK）

完整文档：[docs/SDK.md](../docs/SDK.md)（API 全量）· [docs/TOOL-REPO.md](../docs/TOOL-REPO.md)（工具仓库规范 + 发版）

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
