# A-Kit 插件化架构（研究结论 + 实施方案）

> 状态：**研究完成，方案待你点头**
> 日期：2026-10-21
> 取代：`MENUBAR-BOARD.md` 里的「跨进程镜像 / 真身弹出」路线

---

## 0. 结论

**插件化成立，而且是我目前见过唯一能真正做到"完整显示工具原本界面"的路。**

我在本机跑了三组实验（不是查资料，是真编译真运行）：

| 实验 | 结果 | 证据 |
|---|---|---|
| dylib 插件 + NSView 嵌入宿主窗口 | ✅ 通过 | `ToolMenuView` 原样渲染在宿主里，勾选框都在 |
| **SwiftUI** 视图跨 dylib 嵌入 | ✅ 通过 | `NSHostingView<ToolMenuSwiftUI>` 正常渲染 |
| Hardened Runtime 下加载 | ⚠️ 需一个 entitlement | 无 entitlement 时被拒（Team ID 不一致）；加 `disable-library-validation` 后通过 |

关键含义：**工具的界面不需要"镜像"、不需要"弹出"、不需要截图，它就是 A-Kit 面板里的一个普通 NSView。**
同进程，同一棵视图树，hover、点击、动画、状态绑定全部原生。

---

## 1. 为什么这条路能消除所有旧问题

旧方案（跨进程）的三个死结，插件化后**同时消失**：

| 旧问题 | 插件化后 |
|---|---|
| 没有跨进程共享 NSView 的公开 API | 不需要跨进程——同一个进程 |
| 工具要维护两份菜单（NSMenu + AKMenuItem）→ 必然漏项 | 只有一份 View，工具自己和 A-Kit 用的是同一个 |
| Hub 有"摘要"决定权（只摊 2 个 chip） | Hub 只负责摆放，不裁剪内容 |
| 真身弹出要 activate、面板要让位、会闪 | 没有这回事，就在面板里 |
| 需要屏幕录制 / 辅助功能权限 | 零权限 |

A-Sweep 漏 3 项那个问题（原生 8 项注册 5 项），在插件化下**从根上不可能发生**。

---

## 2. 整体架构

### 2.1 形态变化

```
以前：A-Kit 是个"协议外挂"
     工具 --(JSON over unix socket)--> Hub 重绘菜单

现在：A-Kit 是个"宿主"
     Hub --(dlopen)--> 工具插件 --(返回 NSView)--> Hub 直接显示
```

### 2.2 目录

```
A-Kit.app
└── Contents/
    ├── MacOS/AKitHub
    ├── Frameworks/AKitPluginKit.framework     ← 插件契约（宿主与插件共用）
    └── Resources/

~/Library/Application Support/A-Kit/
├── hub.sock                                   ← 保留，给 L1 轻量工具用
├── Plugins/
│   ├── com.aibao.ASweep.akitplugin/
│   │   ├── Contents/Info.plist
│   │   ├── Contents/MacOS/ASweepPlugin       ← dylib（MH_DYLIB）
│   │   └── Contents/Resources/…
│   └── com.askb.NetPulse.akitplugin/
├── layout.json                                ← 落点 / 排布配置
└── crash-sentinel.json                        ← 插件崩溃哨兵
```

### 2.3 三档接入深度（工具自己选）

| 档 | 是什么 | 适合 | 界面保真度 |
|---|---|---|---|
| **L1 数据** | 现有 unix socket 协议，只推状态和菜单数据 | 第三方、不想改代码 | Hub 重绘 |
| **L2 视图** | 插件提供 `NSView`（AppKit 或 SwiftUI） | **自家工具，主推** | 100% 原样 |
| **L3 全权** | 插件提供视图 + 菜单栏图标 + 后台任务 + 事件订阅 | 完整 app 级工具 | 100% 原样 |

L1 保留不删——它是"别人愿意接但不想打包"的入口。L2/L3 是自家工具的主形态。

---

## 3. 插件契约（ABI）

### 3.1 为什么用 `@objc protocol` 而不是纯 Swift

纯 Swift 的 class/protocol 跨 dylib 传递会绑定编译器版本和 metadata 布局。
走 Objective-C runtime 就绕开了：宿主和插件各自编译，按**类名/协议名**在运行时对上。

代价：协议方法签名必须是 ObjC 兼容的（不能有 Swift struct、泛型、`String` 用 `NSString`）。
这个代价完全值得。

### 3.2 入口

```swift
// 插件必须导出这一个 C 符号
@_cdecl("akit_plugin_main")
public func akit_plugin_main(_ hostPtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let host = Unmanaged<AnyObject>.fromOpaque(hostPtr).takeUnretainedValue() as! AKPluginHost
    return Unmanaged.passRetained(ASweepPlugin(host: host)).toOpaque()
}
```

### 3.3 描述符协议

```swift
@objc(AKPluginDescriptor)
public protocol AKPluginDescriptor: NSObjectProtocol {
    var pluginId: String { get }          // com.aibao.ASweep
    var displayName: String { get }       // A-Sweep
    var version: String { get }           // 0.5.0
    var abiVersion: Int32 { get }         // 1

    /// 菜单栏图标（模板图，18×18）
    func statusItemImage() -> NSImage?

    /// 面板里的完整界面 —— 就是你原本的菜单栏 popover 内容
    func makePanelView(width: CGFloat) -> NSView

    /// 用户点菜单栏图标时弹的界面（可选；返回 nil 就复用面板）
    func makePopoverView(width: CGFloat) -> NSView?

    /// 一行状态（折叠态显示）
    func statusText() -> String?

    func activate()                       // 插件被加载
    func deactivate()                     // Hub 退出 / 插件被禁用
}
```

### 3.4 宿主协议（插件反向调用）

```swift
@objc(AKPluginHost)
public protocol AKPluginHost: NSObjectProtocol {
    func requestLayoutRefresh()                    // 我的高度变了
    func setStatusText(_ text: String?)            // 更新折叠态那一行
    func setStatusItemImage(_ image: NSImage?)     // 换菜单栏图标
    func presentFullPanel(forPluginId id: String)  // "打开我的完整界面"
    func openWindow()                              // 让我开自己的主窗口
    func emit(_ event: String, payload: [String: String])
    func log(_ message: String)
}
```

### 3.5 版本校验

宿主 dlopen 后先调 `akit_plugin_main`，拿到描述符读 `abiVersion`，不匹配就 `dlclose` 并标记「需要更新」。
**不匹配绝不加载**——避免用旧 ABI 的插件把 Hub 弄崩。

---

## 4. 工具怎么做成插件（一份代码两个壳）

以 A-Sweep 为例：

```
ASweep/
├── Sources/
│   ├── ASweepCore/          ← 引擎 + 状态 + 所有视图（不含壳）
│   ├── ASweepApp/           ← 独立 app 壳：NSApplication + NSStatusItem
│   └── ASweepPlugin/        ← 插件壳：导出 akit_plugin_main，返回 NSView
```

同一个 `ASweepMenuView`（SwiftUI）：
- 独立运行时塞进自己的 `NSPopover`
- 插件形态下由 `makePanelView` 返回，塞进 A-Kit 面板

**壳里做的事对比：**

| | 独立 app | 插件 |
|---|---|---|
| 启动 | `NSApplication.run()` | 不调，宿主在跑 |
| 菜单栏图标 | 自己建 `NSStatusItem` | 交给 A-Kit（`hubbar`） |
| 显示界面 | 自己开 `NSPopover` | 返回 `NSView` 给宿主 |
| 主窗口 | 自己开 | 调 `host.openWindow()` 后自己开 |
| 状态 | 自己的 `AppState` | 同一个 `AppState` |

关键：**插件不是阉割版，是"无壳版"**。业务代码一行不改。

### 4.0 独立启动 / 两个版本的关系（重要）

先把三个容易混淆的事分清：

| 问题 | 答案 |
|---|---|
| `.akitplugin` 能双击启动吗？ | **不能。** 它是 dylib，没有 `main`、没有进程。双击它什么都不会发生 |
| 插件化之后 A-Sweep 还能独立启动吗？ | **能，但靠的是 `.app` 壳，不是插件**。`both` 模式下 app 和插件一起装，app 照旧双击可用 |
| 两个版本功能一样吗？ | **业务功能完全一样**，区别只在"壳"和"能借到什么" |
| 能同时启动吗？ | **不能，必须互斥**（原因见 4.1） |

**关系一句话**：一份业务代码（`ASweepCore`）＝ 一个盒子；独立 app 和插件是**两个不同的壳**，盒子只有一个，壳可以换。

| | 软件版 `.app` | 插件版 `.akitplugin` |
|---|---|---|
| 本质 | 独立进程 | dylib，跑在 A-Kit 进程内 |
| 怎么启动 | 双击 / 登录项 / Spotlight | A-Kit 启动时 `dlopen` |
| A-Kit 没装或没运行时 | 正常用 | **根本不存在**（发不发挥作用取决于 Hub） |
| 菜单栏图标 | 自己建 `NSStatusItem` | A-Kit 代持（`hubbar`）或收进面板 |
| 主窗口 | 自己开 | 自己开（经 `host.openWindow()`），窗口归属 A-Kit |
| 崩溃影响 | 只崩自己 | **连 A-Kit 一起崩** |
| 更新 | 各自检查更新 | 跟着 app 一起更新（同一个包） |
| 额外能力 | 无 | 跨工具事件总线、统一安装/回滚、菜单栏代持、Hub 的面板样式 |

**结论**：插件不是"取代 app"，是"当 A-Kit 在场时换一套外壳"。A-Kit 挂了/没装，工具回到 app 壳，功能一个不少。

### 4.1 不能同时跑 —— 单实例仲裁

不设互斥会出人命，尤其是 A-Sweep：

- 两个实例各有一份 `AppState` → 状态不一致（一个显示"正在清理"，另一个显示空闲）
- 两个实例都跑引擎 → **同时扫描/清理同一个目录**，这不是性能问题，是数据安全问题
- 两个菜单栏图标、两份定时器、两次上报

插件和 app 是**两个独立地址空间**，谁也看不见谁，所以只能靠**文件锁 + 协商**。

```
~/Library/Application Support/A-Sweep/instance.lock     ← flock(LOCK_EX | LOCK_NB)
```

**规则：谁拿到锁，谁活着。**

| 情形 | 行为 |
|---|---|
| 只有 app | app 拿锁 → 正常独立运行（跟现在一模一样） |
| 只有 A-Kit | A-Kit 加载插件 → 插件拿锁 → 激活 |
| app 先跑，A-Kit 后启动 | 插件拿不到锁 → **不激活**，面板里显示「A-Sweep 正在独立运行」+ 一个「接管」按钮 |
| A-Kit 先跑，用户双击 app | app 拿不到锁 → 通过 socket 请求 Hub `presentFullPanel("com.aibao.ASweep")` → **A-Kit 面板弹出并聚焦到它**，app 自己退出 |
| 点「接管」 | Hub 请 app 优雅退出（保存状态）→ app 释放锁 → 插件拿锁 → 插件接管状态 |

用户体验上很顺：**双击 app 时如果 A-Kit 在管它，你看到的就是 A-Kit 把它的面板打开**，不会冒出第二个实例。

反过来，从 A-Kit 里点一个正在独立运行的工具，也不是硬抢，而是提示「它正在独立运行，要接管吗」。

### 4.2 一个必须处理的坑

工具代码里到处都是 `NSApplication.shared`。插件形态下它返回的是 **Hub 的 NSApplication**，直接调 `.run()` 或 `.terminate()` 会把 Hub 干掉。

对策：`ASweepCore` 里不出现 `NSApplication.shared`，需要的地方走一个 `AKShell` 抽象：

```swift
protocol AKShell {
    func run()                    // app: NSApp.run() / plugin: 空实现
    func terminate()              // app: NSApp.terminate / plugin: host.deactivate()
    func makeStatusItem() -> Any? // app: 真建 / plugin: nil（Hub 代持）
    func present(_ view: NSView)  // app: NSPopover / plugin: host.requestLayoutRefresh()
    func acquireInstanceLock() -> Bool   // 两边都实现，见 4.1
}
```

两个壳各实现一份，`ASweepCore` 只依赖协议。

### 4.3 插件形态下，A-Sweep 的主窗口去哪了

这是个容易被忽略、但会直接影响体验的问题。

插件跑在 A-Kit 进程里，它开的任何 `NSWindow` 都**属于 A-Kit**：Dock 图标是 A-Kit 的、⌘Tab 切到 A-Kit、⌘Q 退的是 A-Kit。
用户在 A-Sweep 窗口里按 ⌘Q 结果把整个 A-Kit 退了，这不能接受。

所以定一条规则：

> **插件不开自己的主窗口。插件的"完整界面"是 A-Kit 控制台里的一个工具页。**

```
点卡片 → A-Kit 主窗口打开，切到「A-Sweep」页
        页内容 = 插件的 makeFullView() 返回的 NSView
```

对应地，插件描述符里除了 `makePanelView`（小，菜单栏尺寸）还要有：

```swift
/// 控制台里的完整界面（大，整页）
func makeFullView() -> NSView
```

尺寸差异靠 SwiftUI 自适应解决：同一个 `ASweepRootView`，塞进 336pt 宽的面板就是菜单样式，塞进 1000pt 宽的页面就是完整样式（用 `@Environment(\.akitSurface)` 微调密度）。

主窗口形态只保留给**独立 app 壳**。这样两条路各归各位：

| | 菜单栏面板 | 完整界面 |
|---|---|---|
| 独立 app | 自己的 `NSPopover` | 自己的 `NSWindow` |
| 插件 | A-Kit 面板里的卡片 | **A-Kit 主窗口里的工具页** |

顺带一个好处：A-Kit 的"控制台"终于名正言顺了——它不只是装/删工具的地方，也是**每个工具的完整界面所在地**。

### 4.4 A-Kit 崩了，工具会怎样

- 插件代码随 A-Kit 进程一起消失，**不留任何残留**（没有守护进程、没有后台任务）
- 下次双击 `A-Sweep.app` 正常启动，拿到实例锁，跟没装 A-Kit 一样
- 唯一影响：如果刚才有长任务在跑（比如正在清理），会中断

所以插件形态**不增加任何持续性依赖**。这也是它比"注入别人的进程"安全得多的原因。

---

## 5. 分发与安装

### 5.1 三种安装模式（manifest 里声明）

| `installMode` | 下载内容 | 落地 | 适用 |
|---|---|---|---|
| `app` | .app | `~/Applications` | 老工具、纯独立 |
| `plugin` | .akitplugin（zip） | `Plugins/` | 纯插件，无独立 app |
| **`both`（推荐）** | .app（内含 .akitplugin） | app 进 Applications，插件注册进 Plugins | 既能在 Hub 里用，也能独立跑 |

`both` 是我推荐的默认：**装一个 app，两种活法**。Hub 不在时工具自己跑，Hub 在时接管。

`both` 的物理结构 —— 插件藏在 app 包里，天然同版本：

```
A-Sweep.app/
└── Contents/
    ├── MacOS/A-Sweep
    └── PlugIns/
        └── ASweep.akitplugin/          ← 插件住这儿
            ├── Contents/Info.plist
            └── Contents/MacOS/ASweepPlugin
```

A-Kit 安装时**不拷贝，建软链**：

```
~/Library/Application Support/A-Kit/Plugins/com.aibao.ASweep.akitplugin
  → ~/Applications/A-Sweep.app/Contents/PlugIns/ASweep.akitplugin
```

软链而不是拷贝，理由：app 一更新，插件跟着更新，永远不会出现"app 是 0.5、插件是 0.4"的错位。
代价：app 被删/被移走后软链悬空 → 加载时检测到就标记「工具已卸载」并自动清理，不会崩。

### 5.2 安装流程（改造现有 Installer）

```
下载 zip → 校验 sha256 → 解包
  → 找到 *.app：验签名 → 移到 ~/Applications
  → 在 app 的 Contents/PlugIns/ 里找 *.akitplugin
       → 验签名 → 在 Plugins/ 建软链
  → 写 manifest 记录（pluginId / appBundleId / version / abiVersion / 软链路径）
  → 热加载（dlopen 后立即出现在面板里，不用重启 Hub）
```

签名校验必须做：插件是**在 Hub 进程里执行的代码**，等于最高的信任级别。任何来源不明的插件都是全权后门。

### 5.3 签名要求（实验已验证）

| 场景 | 要求 |
|---|---|
| 本地 ad-hoc 分发 | 能加载，无额外要求 |
| Hardened Runtime + 公证 | **必须**加 `com.apple.security.cs.disable-library-validation`，否则 Team ID 不一致就会被拒 |
| 想更严 | 要求插件与 Hub 同 Team ID 签名（放弃 entitlement，安全性最高） |

我的建议：**加 entitlement**，因为你的工具都是自己签的、将来可能换证书；同一 Team 的硬约束会在换证书时全线崩。

---

## 6. 菜单栏代持（hubbar）

现在这一步变得很自然：

```
Hub 创建 N 个 NSStatusItem，每个画一个工具的图标
                ↓ 点击
        展开 Hub 面板并聚焦到该工具
        （或者直接弹它自己的 popover）
```

- **顺序**：由 `layout.json` 决定，用户在编排页拖拽 → Hub 按顺序创建 statusItem（系统按创建顺序排布，所以可控）
- **图标**：插件的 `statusItemImage()`
- **点击行为**：每个工具可配 —— `展开面板` / `弹 popover` / `执行默认动作`
- **宽度**：默认 24pt，可按工具配（有的工具想显示文字，如网速）
- **收进看板**：从 `hubbar` 切到 `board`，Hub 释放对应 statusItem，图标消失

> 注：`bar`（工具自持图标）模式下 Hub 无法控制顺序——这是系统限制，不是设计选择。想让顺序完全可控，就得用 `hubbar`。

---

## 7. 面板排布（你要的"多种形式 + 每个工具自定义"）

### 7.1 三种面板形态（全局切换）

| 形态 | 长什么样 | 适合 |
|---|---|---|
| **卡片流** `cards` | 每个工具一张卡，各自展开/折叠 | 工具少（≤6），想看细节 |
| **手风琴** `accordion` | 一次只展开一个，其余一行 | 工具多，聚焦当前 |
| **紧凑列表** `compact` | 一行一个，点开浮层 | 工具很多，只想快速跳转 |

### 7.2 每个工具独立配置

```json
{
  "pluginId": "com.aibao.ASweep",
  "display": "expanded",        // expanded | collapsed | hidden
  "slot": "hubbar",             // bar | hubbar | board | hidden
  "clickBehavior": "panel",     // panel | popover | default
  "statusItemWidth": 24,
  "order": 1
}
```

- `display` 决定**在面板里**怎么显示（你要的"哪些默认展开、哪些折叠、哪些隐藏"）
- `slot` 决定**在系统菜单栏**怎么显示
- 两者独立：可以"菜单栏有图标 + 面板里折叠"，也可以"菜单栏没有 + 面板里常驻展开"

### 7.3 记忆展开状态

用户手动展开/折叠某个工具后，覆盖默认值，下次打开保持。右键卡片「重置为默认」。

---

## 8. 生命周期与崩溃

### 8.1 加载顺序

```
Hub 启动
 → 读 crash-sentinel（上次是否非正常退出？）
 → 扫描 Plugins/
 → 逐个 dlopen + ABI 校验（不匹配就跳过，不加载）
 → 实例化描述符 → 调 activate()
 → 面板首次展开时才 makePanelView（懒加载，不拖慢启动）
```

### 8.2 崩溃隔离（诚实说：没有）

同进程插件崩了 = Hub 崩。这是这条路唯一的真实代价。

缓解措施（能做到的）：
1. **崩溃哨兵**：启动时写 `{loading: [pluginA]}`,正常退出删除。下次启动发现哨兵还在 → 上次是加载 pluginA 时崩的 → **自动禁用 pluginA** 并提示
2. **插件调用全部 try-catch 化**：ObjC 异常能捕获（`@try/@catch`），Swift 的 `fatalError` 捕获不了
3. **建议插件不要在主线程跑重活**：引擎类操作走自己的队列（A-Sweep 本来就该这样）
4. **手动禁用开关**：设置页能关掉某个插件

如果哪天真的被崩烦了，还有退路：**把重活拆成 XPC 子进程**，插件只留 UI。这个不急，现在不做。

### 8.3 卸载

`dlopen` 后不能 `dlclose`（NSView 还活着）。所以：
- 卸载 = 标记禁用 + 下次启动不加载 + 删文件
- 界面上"卸载需要重启 A-Kit"

---

## 9. 迁移动线

### 第 1 步：契约先立（A-Kit 本体）

1. 新建 `AKitPluginKit` target：`AKPluginDescriptor` / `AKPluginHost` / 加载器 / ABI 校验
2. Hub 加插件管理器：扫描、加载、懒创建视图、崩溃哨兵
3. 面板改版：卡片流 / 手风琴 / 紧凑列表
4. 落点配置 + 编排页 + hubbar 代持
5. **文档重写**：`docs/SDK.md` → 《工具接入指南》，L1/L2/L3 三档写清楚；给一个能编译的示例插件（现在的 DemoTool 正好改造成插件样例）

这一步做完，Hub 侧就绪。

### 第 2 步：拿 A-Sweep 试点

1. 拆 `ASweepCore`（业务 + 视图）与壳
2. 新增 `ASweepPlugin` target，导出 `akit_plugin_main`
3. 把现在那段手写 5 项菜单（`ASweepMain.swift:287-298`）删掉——**不再需要注册菜单**
4. 菜单视图改成 SwiftUI，两个壳共用
5. 验证：Hub 面板里看到的菜单 = A-Sweep 自己 popover 里的菜单，逐项对上

### 第 3 步：NetPulse 跟上

它最适合验证 hubbar（常驻菜单栏 + 实时数字）。

### 第 4 步：其余工具逐个接

---

## 10. 风险

| 风险 | 概率 | 影响 | 对策 |
|---|---|---|---|
| 插件崩溃拖垮 Hub | 中 | 高 | 崩溃哨兵 + 自动禁用 + 建议 XPC 拆分重活 |
| SwiftUI 宏在插件 target 里编译异常 | 中 | 中 | 实验时踩到过（`@State` 在裸 swiftc 下找不到宏插件）；用 Xcode 工程/SPM 构建就正常 |
| 插件与 Hub 的 Swift 运行时版本不一致 | 低 | 高 | 全走 ObjC 协议面；文档要求同版本工具链构建 |
| 换签名证书导致插件全失效 | 中 | 高 | 加 `disable-library-validation`，已验证可行 |
| 插件太多、菜单栏塞不下 | 中 | 低 | hubbar 有数量上限提示，超出自动收进看板 |
| 用户装到恶意插件 | 低 | 极高 | 安装前验签名 + 明确提示"插件在 Hub 进程内执行" |

---

## 11. 不做的事

- **XPC 拆分重活**：现在不做，等真被崩烦了再说
- **L1 协议废弃**：保留，给不愿打包的第三方
- **旧协议兼容层**：你说不做，那就 v2 硬切，直接改工具
- **跨进程镜像 / 真身弹出 / 截图**：全部放弃，插件化取代

---

## 12. 一个附带好处

`MOLE_EMBEDDED`（A-Sweep 里那个还没消费的内置引擎变量）在插件化下更顺了——A-Sweep 插件可以直接用 Hub 里的引擎通道，不用自己带一份 Mole。
这条以后单独议。
