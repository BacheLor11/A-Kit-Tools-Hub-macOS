# 接入 A-Kit · 开发者指南

> 适用 A-Kit 0.3+ · 协议 `schemaVersion: 1`
> A-Kit 是 macOS 菜单栏工具的统一控制台。接入之后，你的工具可以把菜单交给 A-Kit 渲染、跟别的工具收发事件，还能被用户用一个 GitHub 链接直接装上。
>
> **你的工具留在你自己的仓库里**。A-Kit 不收录工具源码，两侧只靠 SDK + `akit.json` + 一个 Release 发生关系；仓库规范见 [TOOL-REPO.md](TOOL-REPO.md)。

---

## 一、接入能得到什么

| 能力 | 说明 |
|---|---|
| 菜单栏托管 | 用户装了 A-Kit 时，你的图标自动收进 A-Kit 的卡片面板；没装就完全照旧 |
| 状态显示 | 卡片上显示你上报的一句话状态（"正在录制" "已暂停"），不用自己挤在图标上 |
| 事件总线 | 跟其他工具互通：比如网络监控发现断网，通知下载工具暂停 |
| 一键安装 | 仓库根目录放一个 `akit.json`，用户把仓库链接粘进 A-Kit 就能装、能自动更新 |
| 零权限 | 不需要辅助功能、不需要屏幕录制、不注入任何进程 |

**接入成本**：一个文件 + 20 行代码。

---

## 二、五分钟接入

### 2.1 拿到 SDK

**方式 A：单文件（推荐给独立 app）**

把 [`SDK/AKitStatusKit.swift`](../SDK/AKitStatusKit.swift) 拖进 Xcode 工程，勾上 target。
它只 `import Foundation`，零第三方依赖，Swift 5.9+ / macOS 13+。

**方式 B：SwiftPM**

```swift
dependencies: [
    .package(url: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS.git", from: "0.3.0")
],
targets: [
    .target(name: "MyTool", dependencies: [
        .product(name: "AKitStatusKit", package: "A-Kit")
    ])
]
```

### 2.2 报到

在 `applicationDidFinishLaunching`（或你创建完 `NSStatusItem` 之后）调用：

```swift
import AKitStatusKit

AKHubClient.shared.start(info: AKToolInfo(
    bundleId: Bundle.main.bundleIdentifier ?? "com.example.MyTool",
    name: "MyTool",
    version: "1.0.0",
    status: "空闲",
    menu: [
        AKMenuItem(id: "toggle", title: "开始", kind: .toggle, checked: false),
        AKMenuItem(id: "settings", title: "设置…"),
    ]))
```

调用完什么都不用管：Hub 没开的话，客户端会每 5 秒静默重试一次，**不影响你的主线程，也不影响 app 启动速度**。

### 2.3 收起自己的图标

这是「接管」的关键一步，必须自己做——A-Kit 不会去动别人的 status item：

```swift
AKHubClient.shared.onConnectionChange = { connected in
    statusItem.isVisible = !connected
    // 也可以顺便把 NSMenu 的弹出改走 A-Kit
}
```

### 2.4 处理点击

```swift
AKHubClient.shared.onInvoke = { itemId in
    switch itemId {
    case "toggle": toggle()
    case "settings": openSettings()
    default: break
    }
}
```

**回调一定在主线程**，可以直接碰 UI。

### 2.5 状态变了要推

```swift
// 菜单结构或勾选状态变了：整包重发
AKHubClient.shared.update(menu: newMenu)
// 只改状态文字：轻量通道
AKHubClient.shared.pushStatus("录制中 00:12")
```

两种的区别要说清楚，用错了会很难受：

| | `update(menu:)` | `pushStatus(_:)` |
|---|---|---|
| 作用 | 重发整个注册包 | 只改状态文字 |
| Hub 侧 | 重建这个工具的条目 | 改一个字段 |
| 适合 | 菜单项增删、勾选变化 | CPU、内存、进度、计时这类每秒都在动的数字 |
| 开销 | 中（含菜单树） | 极小，文本没变就不发 |

`update(status:)` 仍然可用，但它内部就是整包重发。**每秒刷一次状态却用 `update(status:)`，等于让 Hub 每秒重建一次你的条目，日志也会被刷满**——A-Sweep 早期就这么踩过。

不推的话，A-Kit 里显示的还是上一次注册的内容。

---

## 三、四条设计原则

1. **可有可无。** `start()` 之后，`isConnected == false` 时你的工具必须和接入前完全一样。不要 `fatalError`，不要弹窗，不要等它。
2. **菜单要短。** A-Kit 的卡片面板每张卡只放得下 2–3 个常用项，其余进子菜单。10 个顶级项 = 用户在面板里翻半天。
3. **`id` 要稳定。** 它是回调的唯一凭据，别用数组下标或本地化后的标题。
4. **别在回调里做重活。** 主线程回调，重活自己丢后台。

---

## 四、菜单项模型

```swift
AKMenuItem(
    id: "toggle",           // 唯一、稳定
    title: "开始",           // 展示文案，可以本地化
    kind: .toggle,          // item / toggle / header / separator
    enabled: true,          // 置灰
    checked: false,         // 仅 toggle 用
    shortcut: "⌘R",         // 仅展示（A-Kit 不代注册快捷键）
    children: nil           // 子菜单
)
```

| `kind` | 用途 | 是否可点 |
|---|---|---|
| `.item` | 普通动作 | ✅ |
| `.toggle` | 勾选开关，`checked` 表示状态 | ✅ |
| `.header` | 分组标题 | ❌ |
| `.separator` | 分隔线 | ❌ |

两个便捷构造：

```swift
AKMenuItem.separator()
AKMenuItem.header("高级")
```

嵌套子菜单直接给 `children`，只建议嵌一层。

> **快捷键**：`shortcut` 目前只用于在 A-Kit 里显示提示文字。真正的全局快捷键请自己在 app 里注册（Carbon / `MASShortcut` 都行），A-Kit 不代劳——否则多工具会抢同一个组合键。

---

## 五、状态与事件

### 状态

`status` 是一句话，显示在卡片副标题：

```swift
AKHubClient.shared.update(status: "已连接 · 32 ms")
AKHubClient.shared.update(status: nil)   // 清空
```

**别把数字刷太勤**，每秒推一次就够；推太频会让面板一直重排。

### 事件总线

声明你关心哪些事件（不带 `subscribes` 就收不到广播）：

```swift
AKToolInfo(..., subscribes: ["netpulse.offline", "netpulse.online"])
```

接收：

```swift
AKHubClient.shared.onEvent = { name, payload in
    if name == "netpulse.offline" { pauseDownloads() }
}
```

发送（会转发给所有订阅者，不会回到自己）：

```swift
AKHubClient.shared.emit("mytool.recording.started", payload: ["duration": "0"])
```

**命名约定**：`<工具名>.<事件>`，全小写，点分隔。`payload` 只能是 `[String: String]`（数字自己转字符串）。

---

## 六、让 A-Kit 能装你：`akit.json`

把这个文件放在**仓库根目录**（也支持 `.akit/tool.json`）。有了它，用户把 `https://github.com/you/YourTool` 粘进 A-Kit 就能一键装好，并且以后能自动更新。

```json
{
  "schemaVersion": 1,
  "id": "mytool",
  "name": "MyTool",
  "tagline": "一句话说明它干什么",
  "bundleId": "com.example.MyTool",
  "category": "tool",
  "minOS": "13.0",
  "asset": "MyTool-*.zip",
  "statusBar": { "supported": true },
  "icon": "https://raw.githubusercontent.com/you/YourTool/main/icon.png",
  "article": "https://askb.app/blog/mytool"
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `schemaVersion` | 建议 | 目前为 `1` |
| `id` | 建议 | 稳定标识，建议小写短横线。不填会用 `owner/repo` |
| `name` | 建议 | 展示名。不填用 Release 标题或仓库名 |
| `tagline` | 否 | 一句话简介，显示在列表里 |
| `bundleId` | **强烈建议** | 装完会拿它和包里实际的 `CFBundleIdentifier` 比对，不一致直接中止——防止下错包 |
| `category` | 否 | `tool` / `game` / `utility` |
| `minOS` | 否 | 显示用的最低系统版本 |
| `asset` | **强烈建议** | 从 Release 多个产物里挑哪个：支持通配（`MyTool-*.zip`）或子串。不填就按文件名打分猜（含 `mac`/`universal` 加分，含 `source`/`symbols` 排除） |
| `statusBar.supported` | 否 | 是否支持菜单栏；也接受直接写 `"statusBar": true` |
| `icon` | 否 | 图标 URL |
| `article` | 否 | 详情页「在博客读这篇」的链接 |
| `sha256` | 否 | 产物哈希。注意它是**固定值**，只对某个特定版本的包成立，一般交给 CI 生成 |

### Release 约定

A-Kit 拉的是 **最新非 draft Release**，从 assets 里挑 `.zip` 或 `.dmg`：

- ✅ `MyTool-1.2.0.zip` → 解压后里面有 `MyTool.app`
- ✅ `MyTool-1.2.0.dmg` → 挂载后里面有 `MyTool.app`
- ❌ `Source code (zip)` — 自动排除
- ❌ `MyTool-1.2.0.pkg` — 需要管理员密码，A-Kit 不代跑 sudo，会直接拒绝

打包命令（保留签名和扩展属性，不要用 `zip -r`）：

```bash
ditto -c -k --sequesterRsrc --keepParent MyTool.app MyTool-1.2.0.zip
```

### 版本号

Tag 建议 `v1.2.3`（A-Kit 会去掉前导 `v` 再比较）。包里的 `CFBundleShortVersionString` 请和 tag 保持一致，否则「有没有新版本」会判断错。

---

## 七、发布前自查

- [ ] `akit.json` 在仓库根目录，`bundleId` 和 `asset` 都填了
- [ ] Release 里至少有一个 `.zip`（内含 `.app`）或 `.dmg`
- [ ] `CFBundleIdentifier` 和 `akit.json` 一致
- [ ] `CFBundleShortVersionString` 与 tag 对应
- [ ] 本机双击能启动
- [ ] 如果发给别人：Developer ID 签名 + 公证（ad-hoc 签名在别人机器上会被 Gatekeeper 拦）

---

## 八、调试

**看日志**：`~/Library/Application Support/A-Kit/Logs/akit.log`
注册成功会有一行 `[hub] register MyTool v1.0.0 items=5`。

**手动摸协议**（Hub 在跑时）：

```bash
printf '{"jsonrpc":"2.0","method":"register","params":{"bundleId":"com.test.x","name":"X","version":"1","menu":[]}}\n' \
  | nc -U ~/Library/Application\ Support/A-Kit/hub.sock
```

**参考实现**：仓库里的 `Sources/AKitDemoTool` 是一个可运行的最小工具；`SDK/Example/IntegratingApp.swift` 是带 `NSStatusItem` 的完整示例。

### 常见现象对照

| 现象 | 原因 |
|---|---|
| 图标不消失 | 没设 `onConnectionChange`，或 Hub 没在跑（`AKHubClient.isHubRunning` 可查） |
| 面板里没我的工具 | 见下一节：接入是三层，缺一层就没卡片 |
| 面板里有张灰底「未登记」卡片 | 协议通了，但 App 不在扫描目录、或 `bundleId` 没进任何清单。点卡片上的「登记」即可 |
| 点了没反应 | `onInvoke` 里的 `id` 和注册时给的不一致 |
| 状态一直是旧的 | 改完没调 `pushStatus(_:)` / `update(status:)` |
| 日志里 register 每秒一条 | 高频刷新走了 `update(status:)`，改用 `pushStatus(_:)` |
| 收不到事件 | `subscribes` 里没声明这个名字 |
| 从链接装失败，提示「和清单对不上」 | `akit.json` 的 `bundleId` 和实际上架的包不一致 |

### 为什么面板里没有我的工具

接入其实是三件事。**只做第一件，卡片不会出现**——0.3.1 及以前就是这样：日志里明明 `register` 成功，面板里一张卡都没有，而你的图标已经让出去了，用户等于找不到入口。

| 层 | 做什么 | 缺了会怎样 |
|---|---|---|
| 协议层 | 调 `start(info:)` 注册 | 日志没有 `register`，A-Kit 完全不知道你 |
| 安装层 | `.app` 在 `scanDirectories` 里（默认 `/Applications`、`~/Applications`） | 扫不到 App，就没有名字、版本和打开路径 |
| 登记层 | `bundleId` 在远端清单 / `tools.local.json` / SDK 导入列表里 | 扫到了也会被过滤掉 |

**0.4.0 起有兜底**：只要协议层通了，即使没装进扫描目录、也没登记，面板里也会出现一张标着「未登记」的卡片——能调菜单、能点开，卡片上还有「登记到本机清单」，点一下写进 `tools.local.json`，下次启动就正式收录。

但别指望兜底。正式分发的工具应该老实做满三层。

---

## 九、兼容性

- 协议目前 `schemaVersion: 1`。新增字段会保持向后兼容：旧版 Hub 会忽略不认识的字段，旧版 SDK 也不受新字段影响。
- SDK 不含任何 Hub 侧逻辑。**Hub 挂了、被卸载、重装，你的工具都不需要改代码。**
- 断线重连是 5 秒一次、无退避上限的静默轮询；如果你觉得太频繁，可以只在需要时 `start()`。

---

## 十、许可

A-Kit 与 SDK 均为 MIT。你可以把 `AKitStatusKit.swift` 直接放进闭源 app 里，不需要署名（当然写了更好）。
