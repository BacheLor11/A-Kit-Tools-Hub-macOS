# 把工具接进 A-Kit · 插件指南

> 适用 A-Kit 0.5+ · 插件 ABI `1`
> 目标：让你的工具原本的菜单栏界面，**原封不动地显示在 A-Kit 面板里**

---

## 0. 先选一条路

| | L1 协议接入 | L2 插件接入 | L3 双壳（推荐给自家工具） |
|---|---|---|---|
| 做法 | 走 unix socket 报状态和菜单数据 | 编一个 `.akitplugin`（dylib），返回 NSView | 一份业务代码，编两个壳 |
| 界面保真 | A-Kit 重绘（会缩水） | **100% 原样** | **100% 原样** |
| 工具能独立跑 | ✅ | ❌（插件没有进程） | ✅ |
| 改造成本 | 20 行 | 中 | 中 + 一个壳 |
| 适合 | 第三方、不想动工程 | 只在 A-Kit 里跑的工具 | **自家工具都该这样** |

**结论**：自家工具走 L3。A-Kit 不在场时它还是完整 app，A-Kit 在场时它换一套壳。

---

## 1. 五分钟：最小可用插件

### 1.1 加依赖

```swift
dependencies: [
    .package(url: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS.git", from: "0.5.0")
],
targets: [
    .target(name: "MyToolPlugin", dependencies: [
        .product(name: "AKitPluginKit", package: "A-Kit")
    ])
]
```

⚠️ **只依赖 `AKitPluginKit`**，不要依赖 `AKitHostKit`（宿主专用）。后者会让同一个类在进程里出现两份，ObjC runtime 会报 `Class ... is implemented in both ...`，然后出现莫名其妙的类型转换失败。这个坑我踩过。

### 1.2 实现描述符

```swift
import AppKit
import SwiftUI
import AKitPluginKit

final class MyToolPlugin: NSObject, AKPluginDescriptor {
    // ⚠️ 必须等于工具的 bundle id。
    // A-Kit 用它对上「安装层」那份记录，否则你会被当成一个没有 app 的孤儿插件。
    var pluginId: String { "com.example.MyTool" }
    var displayName: String { "MyTool" }
    var version: String { "1.0.0" }
    var abiVersion: Int32 { AKPluginABIVersion }

    var host: AKPluginHost?          // 宿主回调，入口里赋值

    func statusItemImage() -> NSImage? {
        let img = NSImage(systemSymbolName: "wrench", accessibilityDescription: "MyTool")
        img?.isTemplate = true
        return img
    }

    /// 面板里的界面 = 你原本挂在菜单栏上的那份
    func makePanelView(width: CGFloat) -> NSView {
        let v = NSHostingView(rootView: MyMenuView())
        v.frame = NSRect(x: 0, y: 0, width: width, height: panelHeight(width: width))
        return v
    }

    /// 高度由你报，宿主不猜
    func panelHeight(width: CGFloat) -> CGFloat { 128 }

    func makePopoverView(width: CGFloat) -> NSView? { nil }   // 复用 panel 就返回 nil

    /// 控制台里的整页（大尺寸）
    func makeFullView() -> NSView {
        let v = NSHostingView(rootView: MyMainView())
        v.frame = NSRect(x: 0, y: 0, width: 900, height: 640)
        return v
    }

    func statusText() -> String? { "空闲" }
    func activate() {}
    func deactivate() {}
}
```

### 1.3 导出入口

```swift
@_cdecl("akit_plugin_main")
public func akit_plugin_main(_ hostPtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let host = Unmanaged<AnyObject>.fromOpaque(hostPtr).takeUnretainedValue() as? AKPluginHost
    let plugin = MyToolPlugin()
    plugin.host = host
    return Unmanaged.passRetained(plugin).toOpaque()
}
```

符号名必须是 `akit_plugin_main`，一个字符都不能差。

### 1.4 打包

```bash
swift build -c release
Scripts/package-plugin.sh .build/release/libMyToolPlugin.dylib dist \
    com.example.MyTool "MyTool" 1.0.0
```

产出 `dist/MyTool.akitplugin`。软链（或拷）到 `~/Library/Application Support/A-Kit/Plugins/`，重启 A-Kit 就能看到。

---

## 2. 协议参考

### 2.1 `AKPluginDescriptor`（你实现）

| 成员 | 说明 |
|---|---|
| `pluginId` | 唯一标识，建议用 bundle id |
| `displayName` / `version` | 显示用 |
| `abiVersion` | 必须返回 `AKPluginABIVersion`，否则宿主拒绝加载 |
| `statusItemImage()` | 菜单栏图标（模板图 18×18），`hubbar` 模式下宿主用它画图标 |
| `makePanelView(width:)` | **窄界面**，面板里的卡片 |
| `panelHeight(width:)` | 上面那个界面的高度 |
| `makePopoverView(width:)` | 可选，点菜单栏图标直接弹的界面；返回 nil 就复用 panel |
| `makeFullView()` | **宽界面**，控制台里的整页 |
| `preferredPanelWidth()` | 可选，你的面板最少要多宽。宿主取所有工具的最大值，不实现就按 336 |
| `statusText()` | 折叠态那一行字 |
| `activate()` / `deactivate()` | 生命周期 |

### 2.2 `AKPluginHost`（宿主提供，你调用）

| 方法 | 用途 |
|---|---|
| `setStatusText(_:)` | 更新折叠态那一行（高频调也安全） |
| `setStatusItemImage(_:)` | 换菜单栏图标 |
| `requestLayoutRefresh()` | 你的界面高度变了，让宿主重新量 |
| `presentFullPanel(_:)` | 请求打开我的完整界面 |
| `openWindow()` | 请求宿主把主窗口拉到前台 |
| `emit(_:payload:)` | 发事件给其他工具 |
| `log(_:)` | 写日志（自动带插件前缀） |

**所有方法都可以从任意线程调**，宿主内部会 hop 回主线程。

---

## 3. 双壳：同一份代码，两种活法

```
MyTool/
├── Sources/
│   ├── MyToolCore/      ← 业务 + 视图（不碰 NSApplication）
│   ├── MyToolApp/       ← 独立壳：NSApp.run() + 自己的 NSStatusItem
│   └── MyToolPlugin/    ← 插件壳：导出 akit_plugin_main
```

`MyToolCore` 里**不要出现 `NSApplication.shared`**。插件形态下它指向的是 A-Kit，
调 `.run()` 或 `.terminate()` 会把整个 A-Kit 干掉。统一走一个壳抽象：

```swift
protocol Shell {
    func run()                    // app: NSApp.run() / plugin: 空
    func terminate()              // app: NSApp.terminate / plugin: host 释放我
    func makeStatusItem() -> Any? // app: 真建 / plugin: nil（Hub 代持）
    func present(_ v: NSView)     // app: NSPopover / plugin: host.requestLayoutRefresh()
}
```

### 3.1 插件不要自己开主窗口

插件跑在 A-Kit 进程里，它开的 `NSWindow` 属于 A-Kit：Dock 图标是 A-Kit、⌘Tab 切到 A-Kit、
**⌘Q 退的是 A-Kit**。用户在 MyTool 窗口里按 ⌘Q 结果整个 A-Kit 没了，这不能接受。

所以：插件的完整界面走 `makeFullView()`，由 A-Kit 主窗口承载。主窗口形态只留给独立 app。

### 3.2 单实例锁

插件和 app 是两个互不相干的地址空间，但引擎操作的是同一批文件。
两个实例同时清理同一个目录，这不是性能问题，是数据安全问题。

用 `AKInstanceLock`（在 `AKitHostKit` 里，插件可以自己写一份同样的 flock 逻辑）：

```swift
let lock = AKInstanceLock(directory: supportDir)
guard lock.tryAcquire() else {
    // 别人在跑：app 应该请求 Hub 接管后退出；插件应该停在未激活
    exit(0)
}
```

| 情形 | 行为 |
|---|---|
| 只有 app | app 拿锁，正常跑 |
| 只有 A-Kit | 插件拿锁，激活 |
| app 先跑，A-Kit 后启动 | 插件拿不到锁 → 面板显示「正在独立运行」+「接管」按钮 |
| A-Kit 先跑，用户双击 app | app 拿不到锁 → 请求 Hub 弹出面板 → 自己退出 |

### 3.3 工具页：`makeFullView()` 长什么样

A-Kit 0.5.4 起，`makeFullView()` 不是弹窗、不是 sheet，而是**控制台侧栏里的一个页面**：
装一个插件就多一页，点进去是工具自己的完整界面，跟 A-Kit 一起开关、一起退出。
这就是「工具不再作为独立 app 在程序坞里占一个图标」的落点。

插件里想让用户跳过来，调 `host.presentFullPanel(pluginId)` —— 不要自己开窗口。

### 3.4 三个只在插件形态下才会踩的坑

**① 偏好设置要显式指定 suite。**
`UserDefaults.standard` 的域由**进程**的 bundle id 决定。插件跑在 A-Kit 里，
`.standard` 会写到 A-Kit 的域去 —— 用户在独立 app 里设的东西，插件里全部读不到。

```swift
public enum MyPrefs {
    public static let shared = UserDefaults(suiteName: "com.example.MyTool") ?? .standard
}
```

域就是工具自己的 bundle id，所以独立 app 那边不用迁移，两边天然是同一份。

**② 不要用 `Bundle.main` 找自己的资源。**
插件里 `Bundle.main` 是 **A-Kit**：找不到你的 toolchain / 图标 / 版本号，
「别把自己卸了」的保护还会保护错对象。用 `dladdr` 从自己的镜像往上找 `.app`：

```swift
var info = Dl_info()
dladdr(#dsohandle, &info)
var url = URL(fileURLWithPath: String(cString: info.dli_fname))
while url.pathExtension != "app", url.path != "/" { url = url.deletingLastPathComponent() }
// url 就是装着自己的那个 .app（app 内置插件和裸插件都能找到正确的层级）
```

**③ 权限记在宿主账上。**
TCC 认进程不认 dylib。插件要「输入监控 / 完全磁盘访问 / 辅助功能」，
用户得在系统设置里勾 **A-Kit**，独立 app 那份授权不会自动惠及插件。
宿主 Info.plist 里对应的 `NS*UsageDescription` 也要写，否则弹窗没文案。

---

## 4. 常见坑

### 4.1 同进程两份类

插件静态链接了 `AKitHostKit`（或任何含实现类的库），宿主也链接了，
于是 `AKCrashSentinel` 这类类在进程里出现两份：

```
objc[123]: Class _TtC13AKitPluginKit15AKCrashSentinel is implemented in both ...
```

**只依赖 `AKitPluginKit`**（只有协议，没有类），就没事。

### 4.2 SwiftUI 的宏

`@State` 这类宏需要 `swift-plugin-server`。裸 `swiftc` 编译会报
`external macro implementation type 'SwiftUIMacros.StateMacro' could not be found`。
用 `swift build` 或 Xcode 工程就正常。

### 4.3 硬编码高度

`panelHeight` 报小了会截断内容，报大了下面一片空白。
内容变了记得调 `host.requestLayoutRefresh()`。

### 4.4 Hardened Runtime

本地 ad-hoc 分发没问题。**公证分发时宿主必须带**

```
com.apple.security.cs.disable-library-validation
```

否则 Team ID 不一致会被拒：`mapping process and mapped file (non-platform) have different Team IDs`。
（这个我实测过，加上就通。）

### 4.5 崩溃了怎么办

插件和宿主同进程，插件崩 = 宿主崩。A-Kit 有崩溃哨兵：
上次异常退出时正在加载的插件，下次启动会被自动禁用并提示。

所以别在主线程跑重活，引擎类操作放自己的队列。

---

## 5. 检查清单

- [ ] 只依赖 `AKitPluginKit`
- [ ] 导出了 `akit_plugin_main`
- [ ] `abiVersion` 返回 `AKPluginABIVersion`
- [ ] `panelHeight` 和实际内容对得上
- [ ] `MyToolCore` 里没有 `NSApplication.shared`
- [ ] 插件不开自己的主窗口
- [ ] 抢了 `instance.lock`
- [ ] 面板界面和独立运行时是**同一份 View**（不是抄两遍）
