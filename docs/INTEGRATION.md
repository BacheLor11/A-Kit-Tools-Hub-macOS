# 把工具接入 A-Kit

这份文档已经并入更完整的 **[SDK.md](SDK.md)**，这里只留一个入口和三条原则。

1. **可选**：装不装 A-Kit，工具都得能跑。连不上就什么都不做。
2. **可退**：Hub 挂了、退出、卡死，工具要能自己把图标挂回来（SDK 5 秒重试 + `onConnectionChange`）。
3. **零权限**：不申请辅助功能，不注入别人的进程。

```swift
import AKitStatusKit

AKHubClient.shared.onConnectionChange = { connected in
    statusItem.isVisible = !connected
}
AKHubClient.shared.onInvoke = { itemId in handle(itemId) }
AKHubClient.shared.start(info: AKToolInfo(
    bundleId: Bundle.main.bundleIdentifier ?? "",
    name: "MyTool", version: "1.0.0",
    menu: [AKMenuItem(id: "toggle", title: "开始", kind: .toggle)]))
```

- 完整 API、菜单模型、事件总线、`akit.json` 规范、发布自查、排错表 → [SDK.md](SDK.md)
- 单文件 SDK 与示例 → [../SDK](../SDK)
