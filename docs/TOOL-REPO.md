# 工具仓库该长什么样

A-Kit 的仓库里**只有引擎**：Hub.app、`akit` CLI、单文件 SDK、文档。一个具体工具都不带。

工具都住在各自的仓库里。那个仓库只要满足三件事——**能独立跑、能自描述、能发 Release**——
任何人在 A-Kit 里粘上它的地址就能装、能更新：

```
https://github.com/你的名字/MyTool
```

这份文档写的就是「那个仓库」要遵守的约定。

---

## 一句话版本

```
工具仓库 = 你的 app 源码 + 一份 SDK 副本 + 一个 akit.json + 一个 Release（zip 里躺着 .app）
```

四个都有，就是「已接入」。少一个也能装，但识别会变弱：

| 有 | 没有 |
|---|---|
| 精确识别名字 / bundle id / 挑哪个产物，能自动检查更新 | 靠文件名猜，装完才校验 |
| 菜单栏能被 A-Kit 代管 | 只是个普通 app，图标不进面板 |

---

## 1. 目录

```
MyTool/
├── Package.swift
├── Sources/
│   └── MyTool/
│       ├── main.swift
│       ├── StatusItemController.swift
│       └── Vendor/AKitStatusKit.swift     ← 从 A-Kit 复制的单文件
├── Resources/Info.plist
├── Scripts/build.sh                        ← 编出 MyTool.app
├── akit.json                               ← 放仓库根，一起提交
└── .github/workflows/release.yml           ← 打 tag 自动出 zip
```

`akit.json` 的位置是约定的：**仓库根目录**。也认 `.akit/tool.json`，但根目录最省事。

---

## 2. 把 SDK 弄进你的项目

两种，挑一个。都是零运行时依赖。

### 方案 A：复制单文件（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/BacheLor11/A-Kit-Tools-Hub-macOS/main/SDK/AKitStatusKit.swift \
  -o Sources/MyTool/Vendor/AKitStatusKit.swift
```

只 `import Foundation`，没有第三方依赖，不需要 SwiftPM，拖进 Xcode 工程也能用。
缺点：A-Kit 改了 SDK 你得手动更新（协议 schemaVersion 1 已经稳定，字段只加不改）。

### 方案 B：SwiftPM 依赖

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS.git", from: "0.2.0")
],
targets: [
    .executableTarget(
        name: "MyTool",
        dependencies: [.product(name: "AKitStatusKit", package: "A-Kit")]
    )
]
```

会连带把 A-Kit 整个包 clone 下来（Hub 的源码也会在）。不需要的话用方案 A。

---

## 3. 接入：五行，外加一条硬规矩

```swift
import AKitStatusKit

// 你自己的 status item，照常创建
let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
item.button?.image = myMenuBarIcon()

// ① 谁代管谁显示 —— 这一行是「图标收进 A-Kit」的全部秘密
AKHubClient.shared.onConnectionChange = { connected in
    item.isVisible = !connected
}

// ② A-Kit 面板里点了菜单项，从这儿回来
AKHubClient.shared.onInvoke = { itemId in
    switch itemId {
    case "toggle": toggle()
    case "settings": openSettings()
    default: break
    }
}

// ③ 注册：告诉 Hub 你是谁、菜单长什么样、状态栏上写什么
AKHubClient.shared.start(info: AKToolInfo(
    bundleId: Bundle.main.bundleIdentifier ?? "",
    name: "MyTool",
    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
    status: "就绪",
    menu: [
        AKMenuItem(id: "toggle", title: "开始", kind: .toggle, checked: false),
        AKMenuItem(id: "sep", title: "", kind: .separator),
        AKMenuItem(id: "settings", title: "设置…", kind: .item),
    ]
))
```

**硬规矩：没装 A-Kit 时，这五行的效果必须等于零。**

连不上就不连，图标照旧挂在系统菜单栏、点开还是你自己的菜单。
SDK 内部是「连不上 → 5 秒后重试」的静默循环，不弹窗、不写日志噪音、不要权限。
Hub 退出或崩了，`onConnectionChange(false)` 会把你自己的图标挂回去。

> 这条不是洁癖。一个工具要能单独发给人用，不能因为对方没装 A-Kit 就变砖。

想要更细的控制（状态刷新、事件订阅、反向通知 Hub）：

```swift
AKHubClient.shared.updateStatus("12.4 KB/s")            // 刷面板上的那行小字
AKHubClient.shared.updateMenu(myMenuModel())            // 菜单结构变了
AKHubClient.shared.emit("mytool.exported", payload: ["path": "/tmp/a.csv"])  // 发事件
AKHubClient.shared.onEvent = { name, payload in ... }   // 收事件（需在 start 的 subscribes 里声明）
```

完整 API 见 [SDK.md](SDK.md)。

---

## 4. `akit.json`

放在仓库根，格式跟 A-Kit 内部清单里的条目一致，只是单个工具：

```json
{
  "schemaVersion": 1,
  "id": "mytool",
  "name": "MyTool",
  "tagline": "一句话说明这个工具干什么",
  "bundleId": "com.example.MyTool",
  "category": "tool",
  "minOS": "13.0",
  "asset": "MyTool-*.zip",
  "statusBar": { "supported": true },
  "icon": "https://raw.githubusercontent.com/you/MyTool/main/icon.png",
  "article": "https://your.blog/mytool"
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 建议 | 小写短横线。不写就用 `owner-repo` 兜底 |
| `name` | 建议 | 显示名。不写就装完读 `CFBundleDisplayName` |
| `bundleId` | **强烈建议** | **必须和 `Info.plist` 完全一致**。A-Kit 装的时候会比对，不一致直接中止，防止下错包 |
| `tagline` | 建议 | 列表/面板上那行灰字 |
| `asset` | 建议 | 从 Release 产物里挑包的通配，如 `MyTool-*.zip`、`*-universal.zip`。不写就靠文件名猜 |
| `statusBar.supported` | 建议 | `true` 表示支持被 Hub 代管（面板里会显示开关） |
| `minOS` | 可选 | 低于这个版本的系统上会提示 |
| `icon` | 可选 | 绝对 URL。不写就用 app 自己的图标 |
| `article` | 可选 | 博客文章地址，详情页会显示「看文章」 |
| `sha256` | 可选 | 只有一个产物时可以把校验和钉死 |

写错的代价：`asset` 挑不到包 → A-Kit 退化成按大小/文件名猜，猜不到就报「没有 macOS 产物」。
`bundleId` 写错 → 装到一半校验失败（比装完打不开好，但体验也够差）。**发版前跑一次 `akit inspect` 最省心。**

---

## 5. 发 Release

### 规矩

| 项 | 约定 |
|---|---|
| Tag | `v1.2.0`（`v` 会被去掉变成版本号 `1.2.0`；`1.2.0` 也认） |
| 产物 | `MyTool-1.2.0.zip` |
| zip 结构 | **第一层就是 `MyTool.app`**：`ditto -c -k --sequesterRsrc --keepParent MyTool.app MyTool-1.2.0.zip` |
| 也支持 | `.dmg`（A-Kit 自己挂载、把 .app 拷出来、卸载干净） |
| 不支持 | `.pkg` —— 要管理员密码，A-Kit 不代跑 sudo，会直接拒绝并让你手动装 |
| 版本号来源 | Release tag 优先；`Info.plist` 里的 `CFBundleShortVersionString` 用来判断本机装的是哪版 |

多个产物没问题，`asset` 通配负责挑。常见组合：

```
MyTool-1.2.0-universal.zip   ← asset: "*-universal.zip"
MyTool-1.2.0-arm64.zip
MyTool-1.2.0.pkg             ← 忽略，A-Kit 不碰
```

### 一个能用的 workflow

```yaml
name: release
on:
  push:
    tags: ["v*"]
jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: bash Scripts/build.sh            # 产出 build/MyTool.app
      - name: Zip
        run: |
          V="${GITHUB_REF_NAME#v}"
          /usr/bin/ditto -c -k --sequesterRsrc --keepParent build/MyTool.app "MyTool-$V.zip"
          shasum -a 256 "MyTool-$V.zip" > "MyTool-$V.zip.sha256"
      - uses: softprops/action-gh-release@v2
        with:
          files: |
            MyTool-*.zip
            MyTool-*.sha256
```

**签名提醒**：ad-hoc 签名的包发给别人会被 Gatekeeper 拦。A-Kit 装的时候会清 quarantine
（自家包的行为），但如果你打算公开分发，还是办个 Developer ID + 公证更省事。

---

## 6. 别人装上你的工具，走的是这条路

```
粘链接（仓库 / Release 页 / tag / 任意 zip·dmg 直链）
  ↓ 解析：owner/repo、tag、直链
  ↓ 拉 GitHub 最新 Release（带 Token 更好，不然一小时 60 次限流）
  ↓ 读仓库根的 akit.json → 知道你是谁、该挑哪个产物
  ↓ 先给一张预览卡：版本 / 产物 / 大小 / 有没有自描述 / 风险提示   ← 不点确认不下载
  ↓ 下载 → sha256 → 解包 → 读包内 bundleId 比对
  ↓ 落到 ~/Applications → 清 quarantine
  ↓ 写 imported.json（owner/repo/tag/产物地址），以后靠它检查更新
工具启动 → 连 hub.sock → register → Hub 面板里出现你的卡片，你自己的图标隐藏
```

更新是同一套：Hub 每次启动（或你点「检查更新」）看 tag 变没变，变了就把产物地址换掉，界面出现「更新」按钮。
想彻底不管来源了：`akit forget <id>`，app 留着，只是不再追踪。

---

## 7. 发版前自查

```bash
# 只看解析结果，一个字节都不下
akit inspect https://github.com/you/MyTool

# 真装一次（装到 ~/Applications）
akit install https://github.com/you/MyTool

# 确认它被记住了、能追踪更新
akit imported

# 体检：签名 / 公证 / Gatekeeper / 架构 / 最低系统
akit doctor
```

打勾清单：

- [ ] 工具不装 A-Kit 也能正常跑，菜单栏图标正常出现
- [ ] 装了 A-Kit 并启动后，自己的图标消失，A-Kit 面板里能操作它
- [ ] 杀掉 A-Kit，5 秒内图标自己回来
- [ ] 仓库根有 `akit.json`，`bundleId` 跟 `Info.plist` 一致
- [ ] Release 产物是 zip，里面第一层是 `.app`，`asset` 通配能命中
- [ ] `akit inspect` 显示「有 akit.json（可校验、可自动更新）」
- [ ] `akit doctor` 的警告都心里有数（ad-hoc 签名的警告是预期内的）

---

## 8. 别做的事

- **不要把 A-Kit.app 打进你的工具包**。它是宿主，不是依赖；两个人的 Hub 版本还可能不一样
- **不要让工具「必须有 A-Kit 才能启动」**。接了 SDK 也是可选项，没装就得照常工作
- **不要在 `akit.json` 里写本机绝对路径**（`source` 字段只属于 `tools.local.json`，那是每台机器自己的事）
- **不要为了「图标被接管」去申请辅助功能 / 屏幕录制**。协议走 Unix socket，零权限
- **不要改 `akit.json` 的语义让旧版本 Hub 崩**。字段只加不改，`schemaVersion` 现在还是 1

---

## 9. 兼容性

- SDK 协议：`schemaVersion 1`，换行分隔的 JSON-RPC over Unix socket
- `akit.json`：`schemaVersion 1`，未知字段忽略
- A-Kit 最低 macOS 13；工具本身可以是更低或更高，`minOS` 里写清楚就行
- SDK 的公开 API 只增不减；真要做破坏性改动，会同时抬 `schemaVersion` 并保留旧通道

---

相关文档：[SDK.md](SDK.md)（API 全量）· [DESIGN.md](DESIGN.md)（为什么这么设计）· [`../SDK/`](../SDK)（单文件 SDK + 示例）
