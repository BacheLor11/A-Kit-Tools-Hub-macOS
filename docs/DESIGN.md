# A-Kit · 设计方案

> 状态：v0.1.0 已落地（2026-10-21）
> 日期：2026-10-21
> 定位：A宝自研 macOS 工具的「统一控制台」——一个入口管理所有工具，并统一收拢菜单栏

---

## 0. 先说三条技术底线（决定产品长什么样）

### ① 别人的菜单栏图标，技术上无法"真接管"

macOS 没有公开 API 让 AApp 读取、移动、隐藏 **BApp** 的 `NSStatusItem`。现实中的 Bartender / Ice / SaneBar
都是同一套脏手段：

| 手段 | 代价 |
|---|---|
| Accessibility API（AXUIElement）枚举 + 虚拟点击 | 必须申请「辅助功能」权限，且 macOS 26 起更不稳（图标可能被系统塞进 notch 隐藏区、`isVisible` 会误报） |
| 屏外推挤（给图标加超大 length 把它推出屏幕） | 系统挤压（overflow）时会静默改状态，用户拖一下顺序就复位 |
| `autosaveName` 抢占 / ControlCenter 白名单写 defaults | 属于未公开行为，系统更新就断 |

**结论：对第三方 app 只能"引导 + 尽力而为"，不能承诺。**

### ② 但自家 app 可以做到 100% 接管

因为你拥有源码。给工具加一个**协作协议**：hub 在线时，工具自己不建 status item，
把菜单结构通过本地 IPC 交给 hub 渲染；hub 退出就自动回退到自建，工具永远能独立运行。

这条路径干净、稳定、不需要任何系统权限，而且未来每个新工具只要 3 行注册代码。

### ③ 所以本方案的分层是

- **接了 SDK 的工具（自家的，或第三方愿意接的）→ 完全接管**（协议级）
- **没接的工具 → 只做「一键隐藏引导」+（可选）实验性 AX 隐藏**，默认关闭，明确标注实验性

---

## 1. 产品形态

一个 app，两种入口：

```
A-Kit Tools Hub.app
├── 菜单栏常驻图标（点开是统一菜单 / 统一面板）
└── 主窗口（杂志风控制台，可来回切）
```

- 不做 `LSUIElement`：Dock 保留图标，方便 ⌘Tab 切回窗口
- 菜单栏图标可单独关闭（只留窗口），也可「只留菜单栏，关掉窗口」

---

## 2. 三个子系统

### 2.1 Registry —— 清单 / 安装 / 更新 / 卸载

**数据来源（双轨）**

| 轨道 | 内容 | 用途 |
|---|---|---|
| 远程 Manifest | 线上 JSON，含版本、下载 URL、sha256、大小、更新日志、图标 | 判断"有没有新版"、下载 |
| 本地扫描 | 扫 `/Applications`、`~/Applications` 里 `CFBundleIdentifier` 命中白名单的 app，读版本/build | 判断"装没装、装的哪版" |

**Manifest schema（草案）**

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-21T02:00:00Z",
  "tools": [
    {
      "id": "mytool",
      "name": "MyTool",
      "tagline": "一句话说明",
      "bundleId": "com.example.MyTool",
      "category": "tool",
      "repo": "owner/MyTool",
      "icon": "icons/mytool.png",
      "statusBar": { "supported": true, "defaultVisible": true },
      "channels": {
        "stable": {
          "version": "1.2.0",
          "build": 12,
          "minOS": "13.0",
          "url": "https://.../MyTool-1.2.0.zip",
          "sha256": "…",
          "size": 4210000,
          "releasedAt": "2026-10-18",
          "notes": "修复…"
        }
      }
    }
  ]
}
```

**安装流程**

```
下载到 ~/Library/Application Support/A-Kit-Hub/downloads/
  → 校验 sha256
  → 解压到临时目录
  → codesign -dv 校验签名 + 检查 TeamIdentifier 白名单
  → 读到 CFBundleIdentifier 与 manifest 比对（防串包）
  → 移动到目标目录（默认 ~/Applications，避免要 sudo）
  → xattr -d com.apple.quarantine（自家包，去 Gatekeeper 拦）
  → 刷新 LaunchServices
```

**更新流程（运行中替换）**

app 自己不能覆盖自己正在跑的 bundle，标准做法：

```
1. 下载新版到临时目录
2. 写一个 /tmp/akit-swap-<pid>.sh：等 pid 退出 → rm -rf 旧 → ditto 新 → 重启
3. hub 退出自己（或只退出目标 app）
4. 脚本接手完成替换
```

**卸载**：`NSWorkspace.shared.recycle()` 进废纸篓（不硬删），再可选清理
`~/Library/Application Support/<bundleId>`、`~/Library/Preferences/<bundleId>.plist`、`~/Library/Caches/<bundleId>`。

**Dev 模式（很重要，日常最省事的一环）**
在 `tools.local.json`（本机私有，不进仓库）里给工具登记 `"source": { "type": "local", "path": "~/Code/MyTool", "build": "swift build -c release" }`，
界面上直接「重建并安装」——跑构建脚本 → ditto 出 .app → 替换 → 重启。
以后改完代码不用手敲一串命令。**源码路径属于每台机器，所以不进任何随包分发的东西。**

---

### 2.2 StatusBar Hub —— 菜单栏统一

**协议（`AKitStatusKit`，独立 SPM 包，工具 app 依赖它）**

```
工具 app 启动
  → 找 ~/Library/Application Support/A-Kit-Hub/hub.sock
  → 连上：{"method":"register","params":{bundleId, name, menu:[…]}}
  → hub 回：{"result":{"showItem": false, "managed": true}}
  → 工具：showItem=false 时不建自己的 NSStatusItem（或建了设 isVisible=false）
  → 用户点 hub 里这个工具的菜单项 → hub 发 {"method":"invoke","params":{"itemId":"start"}}
  → 工具执行，回 {"result":"ok"}，若菜单有 checkbox 状态变化就主动 publish 一次
  → 工具退出/断线 → hub 标记 offline（灰显，保留位置）
```

- 传输：**Unix Domain Socket + JSON-RPC 2.0**（零配置、可 `nc` 手测、不需要 entitlements）
- 工具端带 **看门狗**：hub 30s 没响应 → 自动回退自建 status item，绝不让工具变砖
- hub 端做 **菜单渲染**：分组（分隔线）、标题项、checkbox、submenu、图标
- 每个工具在 hub 里是一级菜单项，可折叠成子菜单，避免 hub 菜单比原来还长

**布局配置（`layout.json`）**

```json
{
  "groups": [
    { "id": "network",  "title": "网络", "items": ["netpulse"], "collapsed": true },
    { "id": "screen",   "title": "屏幕", "items": ["gtvmic", "passerby"] }
  ],
  "hidden": ["passerby"],
  "clickBehavior": "panel"
}
```

界面支持拖拽排序 / 拖进"隐藏区" / 每项开关，等价于你要的"也可以单独指定显示"。

**第三方实验功能（默认关）**
工具栏里放一个「第三方图标」页：列出通过 AX 能枚举到的 status item，做「尝试隐藏」。
失败就提示"请按住 ⌘ 拖动该图标移出菜单栏"。明确标注 ⚠️ 实验，不保证。

---

### 2.3 Design System —— 博客同款皮肤

从 `ASKB-Blog/src/styles/global.css` 提取的 token，SwiftUI 里做 `AKTheme`：

| Token | Light | Dark |
|---|---|---|
| bg | `#FBFAF7` | `#15171A` |
| surface | `#FFFFFF` | `#202326` |
| ink | `#1A1A1A` | `#ECE9E2` |
| ink-soft | `#5B574E` | `#A8A29A` |
| accent（墨蓝） | `#34557A` | `#7BA3CC` |
| accent2（赭石） | `#B5562E` | `#D98A5E` |
| border | `#E7E2D8` | `#2E3236` |
| radius | 10 | 10 |
| shadow | `0 12 32 rgba(26,26,26,0.08)` | `0 12 32 rgba(0,0,0,0.45)` |

- 标题：`Songti SC`（系统自带 `Songti.ttc`），Bold，letter-spacing 0.01em
- 品牌字：`Zapfino`（系统自带 `Zapfino.ttf`），复现博客左上角 ASKB 那个味道 → 这里写 `A-Kit`
- 正文：`PingFang SC`，行高 1.8
- **桌面端列表不套卡片**：左列小号墨蓝 meta（版本/状态），右列标题+简介，行间 1px border，
  hover 标题变墨蓝 —— 就是博客 `.card` 在 ≥720px 的那套规则，搬过来一模一样
- 深色模式跟随系统（`NSApp.effectiveAppearance`），也可手动切

**窗口结构**

```
┌───────────────────────────────────────────────┐
│  A-Kit (Zapfino)        [搜索]  [☾]           │  吸顶毛玻璃
├──────────┬────────────────────────────────────┤
│ 工具      │  Hero: 大宋体标题 + lede           │
│ 更新 (3)  │  ────────────────────────────────  │
│ 菜单栏    │  2026-10-18   MyTool      1.2.0 ● │
│ 第三方    │  v1.2.0 · 421万 →  已是最新        │
│ 设置      │  ────────────────────────────────  │
│           │  2026-10-16   MyToolPro   1.0.5   │
└──────────┴────────────────────────────────────┘
```

详情页：大宋体标题 + tagline + `[打开] [更新] [卸载]` + 更新日志（prose 排版，二级标题带下边框）

---

## 3. 图标方案

| 用途 | 做法 |
|---|---|
| App 图标 | 用「A宝工具箱」的 `画框.png`（白色相框字标）+ `icon.json` 里的红色渐变（`srgb 1.00,0.23137,0.18824`，竖向 0→0.7 停靠点）合成 1024 PNG → `sips` 出 iconset → `iconutil` 出 `.icns`。脚本 `Scripts/make_app_icon.py`，可复现 |
| 菜单栏图标 | `Resources/MenuBarIconSource.png`（缺省回落 `MarkA.png`）→ 抽 alpha 通道做遮罩 → 生成 18×18 / 36×36 / 54×54 template PNG，`NSImage.isTemplate = true`。系统自动在浅色模式画黑、深色模式画白，选中有反色，无需自己做两套 |

---

## 4. 技术栈

```
SwiftPM（不用 Xcode 工程，跟各工具自己仓库的构建方式一致）
  ├── swift-tools-version: 6.0, platform macOS 13+
  ├── Scripts/build.sh    → swift build + 组装 .app + 签名(ad-hoc) + 出 DMG/ZIP
  ├── Resources/AppIcon.icns, Info.plist(LSUIElement=false, NSStatusItem)
  └── 依赖：无（SwiftUI + AppKit 原生，不引第三方，避免 Gatekeeper/体积问题）
```

为什么不引 Sparkle：我们自己做多工具清单管理，用 Sparkle 反而两套更新逻辑打架。
自己实现的更新器约 300 行，可控。

**目录规划**

```
A-Kit-Tools-Hub/
├── Package.swift
├── Sources/
│   ├── AKitHub/            main entry + App
│   │   ├── App/            主窗口、菜单栏、路由
│   │   ├── Core/           Manifest / Installer / Scanner / Layout / IPC
│   │   └── UI/             Theme、组件、页面
│   └── AKitStatusKit/      给工具 app 用的客户端库（也可独立成 Package）
├── Resources/
├── Scripts/
│   ├── build.sh
│   ├── make_app_icon.py
│   ├── make_menubar_icon.py
│   └── publish.sh          生成 manifest.json + 上传 GitHub Release
└── docs/DESIGN.md
```

**运行期数据**

```
~/Library/Application Support/A-Kit-Hub/
├── hub.sock          IPC
├── manifest.cache.json
├── layout.json
├── downloads/
└── logs/
```

---

## 5. 里程碑

| 阶段 | 交付 | 可验证点 |
|---|---|---|
| **M1 骨架** | 窗口 + 博客皮肤 + 导航 + mock 清单 | 打开就是那个味儿，深浅色都对 |
| **M2 管理** | 扫描本机 + manifest 拉取 + 安装/卸载/更新 + dev 重建 | 真能装上、真能更新、真进废纸篓 |
| **M3 接管** | hub 菜单栏 + `AKitStatusKit` + 接 1 个工具（自家某个菜单栏工具） | 工具自己的图标消失，hub 里能操作它 |
| **M4 铺开** | 多工具接入 + 布局拖拽 + 发布脚本 + 第三方引导页 | 日常真用它 |

---

## 6. 额外建议（你没提但值得做）

1. **工具自注册**：工具首次运行自动往 hub 报到（写 `installed.json`），清单不用手工维护两遍。
2. **`akit://` URL scheme + CLI**：`akit open netpulse`，博客/脚本/快捷指令都能跳。
3. **一键全查更新**，菜单栏图标上挂个小红点（有新版本时）。
4. **诊断页**：每个工具的签名状态、Gatekeeper 状态、最近一次崩溃日志、CPU/内存占用。
5. **Developer ID 签名**：现在 ad-hoc 签名，别人下载会被 Gatekeeper 拦；自己机器无所谓。
   如果以后要发给朋友，建议办个 $99 开发者账号 + 公证，一次性解决。
6. **别做成第二个 Launchpad**：定位就守死"我自己的工具"，不要塞系统 app、不要塞商店应用，否则会变杂。
7. **hub 崩了不能连累工具**：协作协议必须有回退（已在设计里保证）。
8. **菜单栏别变长**：默认按分组折叠，一级最多 3-4 个入口。

---

## 7. 风险清单

| 风险 | 影响 | 对策 |
|---|---|---|
| 第三方图标接管不稳 | 功能看起来"没生效" | 默认关闭 + 明确文案 + 引导 ⌘ 拖拽 |
| 运行中替换 app 失败 | 工具打不开 | 先 ditto 到临时目录校验通过再换；失败回滚备份 |
| hub 卡死不响应 | 工具菜单栏消失 | 工具端 30s 看门狗回退 |
| manifest 被篡改 | 装到野包 | sha256 + 签名 TeamIdentifier 白名单 |
| ad-hoc 签名 | 换机器/别人下载被拦 | 自家机器 `xattr -d quarantine` 自动处理 |


---

## 8. 落地记录（v0.1.0）

### 名字定了
正式名 **A-Kit**，「Tools Hub」只做副标题；bundle id `com.aibao.AKitHub`。

### 最终范围（第一版全做了）
| 原计划 | 状态 |
|---|---|
| 清单 / 安装 / 更新 / 卸载 | ✅ Registry + Installer |
| 博客皮肤 | ✅ Theme.swift 与 global.css 令牌一一对应 |
| 菜单栏接管（完整代理） | ✅ HubServer + AKitStatusKit，注册 / 下发 / 事件三通道自测通过 |
| 面板式菜单栏 + 搜索 | ✅ NSPanel 卡片面板 + ⌘⇧A（Carbon 热键，零权限） |
| 热重载 + 回滚 + 体检 | ⚠️ 回滚、体检、源码重建已做；**文件监听热重载还没做**（下一版） |
| export/import + CLI | ✅ `akit` 二进制，与 GUI 共用 AKitCore |
| 事件总线 / 使用统计 | ⚠️ 事件总线协议通；统计只记了打开次数，UI 还没展示 |
| 博客打通 | ⚠️ 详情页留了「在博客读这篇」入口，发版自动生成日志未做 |

### 与初版设计的偏差
1. **IPC 从「XPC 或 socket 二选一」定为 Unix socket + 换行 JSON**：可 `nc` 手测，不用 entitlements。
2. **面板高度按内容算**，不是固定尺寸：工具少的时候不留大片空白。
3. **菜单栏图标从源字标生成 template**：`画框.png` 是白色「A.」，压成实心 alpha 后系统自动黑白。
4. **SDK 做成单文件 + 零依赖**，直接复制也能用 —— 因为「没装 Hub 也要能跑」是硬要求。
5. **踩坑记录**：`accept()` 在阻塞 socket 上会把串行队列堵死，必须 `O_NONBLOCK`。已写进代码注释。

### 还没做（下一版候选）
- 源码目录监听 → 自动 rebuild（热重载）
- 使用统计页（三个月没开过 → 建议卸载）
- 发版自动写 askb.app 更新日志
- 公证 / Developer ID（要发给别人才需要）

---

## 9. v0.2（2026-10-21）

这一版解决三件事：**别人怎么把工具给我**、**我怎么把别人的工具装上**、**怎么对外开源**。

### 9.1 从链接安装

输入一行地址 → 解析 → 预览 → 安装。支持的写法：

| 输入 | 行为 |
|---|---|
| `https://github.com/o/r` | 取最新 Release，自动挑 macOS 产物 |
| `https://github.com/o/r/releases/tag/v1.2.0` | 指定版本 |
| `https://github.com/o/r/releases/download/v1.2.0/X.zip` | 具体产物，仍保留 repo/tag 以便查更新 |
| `o/r` | 简写 |
| 任意 `http(s)://…/X.zip` / `.dmg` | 直链，不检查更新 |

关键决策：

1. **解析与安装分离**。先 `ImportResolver.inspect` 拿一张候选卡（名字、版本、产物、大小、警告），用户确认后才下载。避免「点了才知道装的是什么东西」。
2. **`akit.json` 优先，没有也能装**。有自描述 → 精确匹配产物 + 校验 bundle id；没有 → 按文件名打分 + 装完读 `Info.plist`，并在预览里明确警告。
3. **记住来源**。装完写 `imported.json`（repo、tag、asset URL），所以「从链接装的」也能检查更新。更新时重新挑产物，不依赖旧 URL。
4. **PKG 不代跑 sudo**。直接拒绝并说明原因，比偷偷弹密码框诚实。
5. **API 可覆盖**（`AKIT_GITHUB_API` / `AKIT_GITHUB_RAW`），既方便本地 mock 测试，也顺手支持了 GitHub Enterprise。

### 9.2 给第三方的接口

- SDK 仍然是**单文件、零依赖**，但补齐了缺失的一半：`emit()`（工具 → Hub）、`isHubRunning`（不建连接先探测）
- Hub 端新增 `event` 处理：收到工具事件后按 `subscribes` 转发，发送者自己不会收到；同时回调 `onEvent` 给界面
- `docs/SDK.md` 是完整文档（接入 / 菜单模型 / 事件 / akit.json 规范 / 发布自查 / 排错表）
- `SDK/` 目录可直接整包发给别人：单文件 SDK + `akit.json` 模板 + 带 `NSStatusItem` 的完整示例
- App 内「第三方」页做成三步引导，代码片段可一键复制

### 9.3 迭代

| 项 | 说明 |
|---|---|
| Dev 热重载 | 2 秒轮询源码目录指纹（跳过 `.build` / `build` / `.git` / `node_modules`），变化即 rebuild + 重启；10 秒冷却避免构建产物自己触发自己 |
| 深色模式 | 之前 `ak` 环境值从没注入过，一直用浅色。现在 `RootView` 按 `colorScheme` 注入，博客令牌的深色版本才真正生效 |
| 使用情况 | 详情页显示打开次数 / 最近使用；超过 90 天没开会在列表里提示 |
| 错误文案 | 403 区分「限流」与其它错误，并直接给出「填 Token」的建议 |

### 9.4 踩坑

- **环境变量代理 ≠ 系统代理**：WorkBuddy 的 `HTTP_PROXY` 只影响 CLI，GUI 的 `URLSession` 走系统设置。所以在终端里 `curl` GitHub 正常、app 里却 403——不是 bug，是出口 IP 不同。判断限流要看 `X-RateLimit-Remaining`，不能只看状态码。
- **mock 比真机更快**：`Scripts/mock_github.py` 假装 GitHub API，能稳定复现「有 akit.json / 没有 / 404」三条分支，不烧真实额度。
- **别把测试包留在用户机器上**：端到端测完要 `forget` + 移废纸篓 + 清 Backups。

---

## 10. 项目边界（2026-10-21 定）

一句话：**A-Kit 是引擎，工具住在别的仓库，两者只靠「一个链接」发生关系。**

```
A-Kit（本仓库）                 工具仓库（各自独立，N 个）
Hub.app / akit / SDK / docs      MyTool.app + akit.json + Release
        └──────── 粘 GitHub 链接 → 预览 → 安装 ────────┘
```

### 为什么要把线划在这儿

初版把「我的三个工具」直接写进了内置清单（`seed-manifest.json`），还带了本机绝对路径。
自己用没问题，一开源就全是问题：

1. **泄漏自己的目录结构**（`/Volumes/.../Agent-Projects/xxx` 这种不该出现在公开仓库）
2. **概念错位**：清单里写着「有 GTVRemoteMic 1.0.5」，但仓库里没有它的源码 —— 别人 clone 下来会是懵的
3. **更新责任不清**：工具的发版节奏归工具自己，跟 Hub 的版本不该绑在一起

所以规则改成：**每个工具自己带 SDK 副本、自己带 `akit.json`、自己发 Release。**
Hub 只认链接，不内置任何工具。这也顺便让「第三方接入」和「自家工具」走完全同一条路——
没有特权路径，协议才算真开源可用。

### 三条数据来源，各管各的

| 来源 | 文件 | 谁写 | 会不会进 Git |
|---|---|---|---|
| 远端清单 | 远端 `manifest.json` | Release 自动生成（只含 A-Kit 自己） | 生成物，不进 |
| 粘链接装的 | `imported.json` | Hub 写入（repo / tag / 产物地址） | 不进，本机数据 |
| 本机私有登记 | `tools.local.json` | 用户手写（本地源码、私货） | 不进，故意放仓库外 |

三者合并成 `effectiveManifest` 后，安装 / 更新 / 卸载 / 体检 / 热重载全部走同一套代码。

### 这一轮随之改掉的东西

- `seed-manifest.json` 清空（`tools: []`），只留格式与说明
- `bundlePrefixes` 默认空、`scanDirectories` 去掉私人路径 —— 谁装了什么由 `imported.json` 说了算，不靠前缀猜
- 新增 `tools.local.json` + `akit local`，Dev 重建 / 热重载的本机路径挪到这儿
- `DemoTool` 从 SwiftPM products 里摘掉：它是协议夹具，不是要分发的工具
- 新增 [`TOOL-REPO.md`](TOOL-REPO.md)：写给「另一个仓库」的规范（目录、Release 命名、发版 workflow、自查清单）
