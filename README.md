# A-Kit

> 自己写的小工具，自己收着。

一个 macOS 工具控制台：**装 / 更 / 删**一处管完，菜单栏图标收成一个，接入的工具由它统一代管。
还能**贴一个 GitHub 链接就把别人的工具装上**。

这不是要上架的商业软件，是我给自己那堆小工具做的一个「家」。开源，随便看。

![工具页](docs/screenshots/01-tools.png)

---

## 这个仓库里有什么，没有什么

A-Kit 只做**引擎**。工具都在各自的仓库里，谁也不捆绑谁。

> 仓库全名是 `A-Kit-Tools-Hub-macOS`，为了跟一堆 `A-Kit-*` 的项目区分开；**软件名就叫 A-Kit**，装的还是这个 app。

```
A-Kit（本仓库）                     工具仓库（各自独立）
├── Hub.app     图形界面 / 菜单栏    ├── MyTool.app    自己的 app
├── akit        CLI                 ├── akit.json     自描述（名字、bundle id、挑哪个包）
├── SDK/        单文件接入库         └── Release       zip 里躺着 .app
└── docs/       协议与规范                    │
        │                                    │
        └──────── 粘一个 GitHub 链接 ─────────┘
                  预览 → 安装 → 记来源 → 以后能查更新
```

**没有：** 任何具体工具的源码、任何人的本机路径、一份「官方推荐工具清单」。
内置清单是**刻意留空**的（`Resources/seed-manifest.json`），只当格式示例；
官方 Release 里的 `manifest.json` 只登记 A-Kit 自己，用于自更新。

**有：** 一套让「别人的工具也能被装上、被代管」的约定 —— 见
[工具仓库该长什么样](docs/TOOL-REPO.md)。

> 换句话说：装了 A-Kit，不代表就有工具；工具得你自己粘链接装。
> 而工具就算一辈子不装 A-Kit，也照常能用。

---

## 它能干什么

**① 工具管理**
- 清单（远端 manifest）与本机扫描双轨：知道有哪些工具、装没装、装的是哪版
- 安装：下载 → sha256 校验 → 解包 → 校验 bundle id → 落到 `~/Applications` → 去 quarantine
- 更新：目标在跑的时候走「延迟替换」脚本，不用先手动退出
- 卸载：进废纸篓，可选连配置文件一起清
- **版本备份与回滚**：每次覆盖前自动备份，默认留 3 份
- **体检**：签名、Hardened Runtime、Gatekeeper、公证、架构、最低系统版本
- **源码重建 + 热重载**：清单里登记本地源码路径，改完文件约 2 秒自动 rebuild、重启（可选）

**② 从链接安装（GitHub）**

![从链接安装](docs/screenshots/07-import.png)

把 `https://github.com/owner/repo`、某个 Release 的地址，或者任意 `.zip` / `.dmg` 直链粘进去：

- 自动问 GitHub 要最新 Release，从一堆产物里挑出 macOS 的那个
- 仓库根目录有 `akit.json` 就精确识别（名字、bundle id、挑哪个包）；没有也能装，靠文件名猜 + 装完读 `Info.plist`
- 装完记住来源，以后能检查更新（tag 变了就把新产物地址换掉）
- 安装前先给你看一张预览卡：版本、产物、大小、有没有自描述、有哪些风险提示

**③ 菜单栏统一**

![面板](docs/screenshots/02-panel.png)

- 一个图标 → 卡片面板；每张卡上直接放常用开关和实时状态，高级项才进子菜单
- `⌘⇧A` 全局唤起（Carbon 热键，**不需要辅助功能权限**）
- 左键开面板 / 右键出原生菜单，可切换
- 深色模式跟随系统（与博客同一套令牌的深色版本）

**④ 接管是「协作」，不是「劫持」**

```
工具启动
  → 找 ~/Library/Application Support/A-Kit/hub.sock
  → 连上就 register（bundleId / 名字 / 版本 / 菜单结构 / 状态 / 订阅的事件）
  → Hub 代管，工具把自己的 NSStatusItem 藏起来
  → 断开或 Hub 挂了 → 工具 5 秒内把图标挂回去
```

**没装 A-Kit 的工具照常工作**，行为与接入前完全一致。接入只是「多了一个可选的上游」，不是依赖。

**⑤ 事件总线（双向）**
工具可以声明 `subscribes`，也可以主动 `emit`。Hub 按事件名转发，发送者自己不会收到。

```swift
AKHubClient.shared.emit("netpulse.offline", payload: ["since": "9"])
```

**⑥ CLI**

```bash
akit list                       # 所有工具与版本
akit updates                    # 只看有更新的
akit install gtvmic             # 按 id 装
akit install https://github.com/owner/repo   # 按链接装
akit inspect owner/repo         # 只看解析结果，不下载
akit imported                   # 从链接装过的工具
akit doctor                     # 体检所有已装工具
akit export x.json              # 换 Mac 时搬配置
```

---

## 关于「接管第三方图标」

**做不到，也不装做得到。**

macOS 没有公开 API 让 A app 读取、移动、隐藏 B app 的菜单栏图标。Bartender / Ice 那类工具靠「辅助功能」权限模拟点击，或把图标推到屏幕外；macOS 26 起系统自己会插手可见性，所以经常失灵。

A-Kit 的选择：

- 自家 / 已接入的工具 → 走协议，稳定、零权限
- 第三方 → 只在「第三方」页给引导（⌘ 拖动移出菜单栏、系统设置里关），明确写清楚不保证

不申请辅助功能、不申请屏幕录制、不注入、不 swizzle 别人的进程。

---

## 把别的工具接进来

**在你自己的仓库里做三件事**，做完这个工具就「已接入」了 —— 别人在 A-Kit 里粘它的地址就能装：

**① 复制 SDK**（单文件，只 `import Foundation`，不进你的依赖树）

```bash
curl -fsSL https://raw.githubusercontent.com/BacheLor11/A-Kit-Tools-Hub-macOS/main/SDK/AKitStatusKit.swift \
  -o Sources/MyTool/Vendor/AKitStatusKit.swift
```

**② 五行接入** —— 关键是「谁代管谁显示」，以及**没装 A-Kit 时效果必须等于零**

```swift
import AKitStatusKit

AKHubClient.shared.onConnectionChange = { connected in
    item.isVisible = !connected          // Hub 接管了 → 自己的图标让位；Hub 没了 → 自己挂回来
}
AKHubClient.shared.onInvoke = { itemId in handle(itemId) }
AKHubClient.shared.start(info: AKToolInfo(
    bundleId: Bundle.main.bundleIdentifier ?? "",
    name: "MyTool",
    version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
    menu: myMenuModel()))
```

**③ 仓库根放 `akit.json`，发一个 Release（zip 里第一层是 `.app`）**

```json
{
  "schemaVersion": 1,
  "id": "mytool",
  "name": "MyTool",
  "tagline": "一句话说明这个工具干什么",
  "bundleId": "com.example.MyTool",
  "asset": "MyTool-*.zip",
  "statusBar": { "supported": true }
}
```

然后自测一遍，不用真装：

```bash
akit inspect https://github.com/you/MyTool     # 只看解析结果，不下载
```

细节全在 **[docs/TOOL-REPO.md](docs/TOOL-REPO.md)**（目录结构、Release 命名、发版 workflow、
`akit.json` 每个字段、打勾清单、别做的事）。协议与 API 全量在 [docs/SDK.md](docs/SDK.md)。

> 边界提醒：A-Kit 不打包你的工具，你的工具也不要打包 A-Kit。
> 那个「可选上游」关系是单向的 —— 工具能独立活，才允许被接管。

---

## 构建

```bash
swift build --disable-sandbox            # 只编译
bash Scripts/build.sh                    # 产出 build/A-Kit.app
bash Scripts/build.sh --install          # 顺手装到 ~/Applications
bash Scripts/build.sh --release          # 出 zip + sha256
```

> `--disable-sandbox` 是因为 Xcode 26/27 的 SwiftPM 编译沙箱在某些环境下会报
> `sandbox-exec: sandbox_apply: Operation not permitted`。

环境：macOS 13+，Xcode 26+（Swift 6）。没有第三方依赖。

App 图标和菜单栏 template 图标已经生成好、提交在 `Resources/`（`AppIcon.icns` / `MenuBarIcon.png`），
所以构建**不需要 Python**。只有想换图标时才跑脚本（这条路径需要 Pillow）：

```bash
python3 Scripts/make_app_icon.py Resources/MarkA.png build       # App 图标
python3 Scripts/make_menubar_icon.py Resources/MarkA.png build   # 菜单栏 template 图标
```

菜单栏图标是 template image，系统自动在浅色模式画黑、深色模式画白。

### 自测

```bash
./.build/release/AKitHub --selftest        # 注册 / 下发 / 事件三通道
./.build/release/AKitHub --snapshot out.png tools   # 离屏渲染任意页面
./.build/release/DemoTool                  # 协议夹具：一个真的会连上来的假工具
```

> `DemoTool` 是测试夹具，不是产品。它不出现在 SwiftPM products 里，也不会被打进 A-Kit.app ——
> 本仓库不分发任何工具，这条线得划清楚。

---

## 清单格式

内置清单是空的（只有格式）。下面这种结构用在**你自己的清单**里 —— fork 后自建工具集，
或者团队内部分发。粘 GitHub 链接装进来的工具不需要写清单，`imported.json` 会自动维护。

```json
{
  "schemaVersion": 1,
  "tools": [{
    "id": "mytool",
    "name": "MyTool",
    "tagline": "一句话说明",
    "bundleId": "com.example.MyTool",
    "statusBar": { "supported": true },
    "channels": {
      "stable": {
        "version": "1.2.0", "build": 12, "minOS": "13.0",
        "url": "https://.../MyTool-1.2.0.zip",
        "sha256": "…", "notes": "修复…"
      }
    }
  }]
}
```

`source`（`{"type":"swiftpm","path":"~/Code/MyTool"}`）是 Dev 重建 / 热重载用的，**别写进仓库** ——
那是每台机器自己的事，写到 `tools.local.json` 里（见下）。清单地址在「设置」里可改，fork 之后可以用自己的。

---

## 目录

```
~/Library/Application Support/A-Kit/
├── hub.sock            # 与工具通信的 Unix socket
├── settings.json
├── layout.json         # 菜单栏分组 / 隐藏状态
├── imported.json       # 从链接装进来的工具（来源、tag、产物）
├── tools.local.json    # 本机私有登记：本地源码路径等，不进 Git
├── manifest.cache.json
├── Backups/<工具>/<版本>/
├── Downloads/
└── Logs/akit.log
```

---

## 已知限制

- **不内置工具**：这是设计，不是缺功能。要工具就粘链接
- 第三方图标接管：不支持（原因见上）
- 只认 Release 产物：不跑仓库里的安装脚本，`.pkg` 一律拒绝（不代跑 sudo）
- GitHub API 未登录时每 IP 每小时 60 次，容易限流 → 设置里可填只读 Token
- 全局快捷键改了要重启 app 生效
- ad-hoc 签名：把 app 发给别人会被 Gatekeeper 拦（自己机器没问题）
- 事件总线只转发 `[String: String]` 的 payload，没有复杂路由

## 路线

- [x] 工具清单 / 安装 / 更新 / 卸载 / 备份回滚 / 体检
- [x] 菜单栏协作协议 + 面板 + 全局热键
- [x] CLI + 配置导入导出
- [x] 源码重建 + 热重载
- [x] 从 GitHub / 直链安装，带来源记忆与更新检查
- [x] 单文件 SDK + 接入文档 + akit.json 规范
- [x] 项目边界：工具各自独立仓库，本仓库只放引擎；本机私有登记挪到 `tools.local.json`
- [ ] 使用统计页（三个月没开 → 建议卸载）
- [ ] 与 askb.app 博客打通（发版自动生成更新日志）

## License

MIT
