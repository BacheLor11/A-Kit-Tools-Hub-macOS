// 一个最小的菜单栏工具：状态栏图标 + 菜单 + 接入 A-Kit
//
// 用法：新建 macOS App（AppKit），把 AKitStatusKit.swift 和这个文件拖进工程，
//      删掉 Main.storyboard 里的窗口，或者直接改 AppDelegate 即可。
//      没装 A-Kit 时行为和普通菜单栏 app 一模一样。

import AppKit
import AKitStatusKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var enabled = false
    private var lastAction = "还没动过"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. 先按普通菜单栏 app 建图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "circle.dashed",
                                           accessibilityDescription: "MyTool")
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = buildNativeMenu()

        connectToAKit()
    }

    // MARK: 接入 A-Kit

    private func connectToAKit() {
        // 2. Hub 接管时就收起自己的图标，Hub 退出就还回来
        AKHubClient.shared.onConnectionChange = { [weak self] connected in
            self?.statusItem.isVisible = !connected
        }

        // 3. Hub 里点了某个菜单项
        AKHubClient.shared.onInvoke = { [weak self] itemId in
            self?.handle(itemId)
        }

        // 4. 收到别的工具发来的事件（需要先在 subscribes 里声明）
        AKHubClient.shared.onEvent = { name, payload in
            NSLog("收到事件 \(name) \(payload)")
        }

        // 5. 报到：把菜单和状态交给 Hub
        AKHubClient.shared.start(info: AKToolInfo(
            bundleId: Bundle.main.bundleIdentifier ?? "com.example.MyTool",
            name: "MyTool",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            status: statusText,
            menu: akitMenu,
            subscribes: ["netpulse.offline", "netpulse.online"]
        ))
    }

    /// 菜单同时喂给两套 UI：自己的 NSMenu 和 A-Kit 的菜单模型。
    private var akitMenu: [AKMenuItem] {
        [
            AKMenuItem(id: "toggle", title: enabled ? "停用" : "启用", kind: .toggle, checked: enabled),
            AKMenuItem(id: "settings", title: "设置…"),
            .separator(),
            AKMenuItem(id: "status", title: lastAction, enabled: false),
            .header("关于"),
            AKMenuItem(id: "about", title: "关于 MyTool"),
        ]
    }

    private func buildNativeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: enabled ? "停用" : "启用", action: #selector(toggle), keyEquivalent: "t")
            .target = self
        menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let status = menu.addItem(withTitle: lastAction, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q").target = self
        return menu
    }

    private func handle(_ itemId: String) {
        switch itemId {
        case "toggle":
            toggle()
        case "settings":
            openSettings()
        case "about":
            NSApp.orderFrontStandardAboutPanel(nil)
        default:
            break
        }
    }

    // MARK: 业务

    private var statusText: String {
        enabled ? "正在运行" : "已停止"
    }

    @objc private func toggle() {
        enabled.toggle()
        lastAction = enabled ? "刚刚启用" : "刚刚停用"

        // 状态变了要推给 Hub，否则 Hub 里显示的还是旧的
        AKHubClient.shared.update(menu: akitMenu, status: statusText)

        // 自己的原生菜单也同步一下
        statusItem.menu = buildNativeMenu()

        // 顺带广播一个事件给别的工具
        AKHubClient.shared.emit("mytool.state", payload: ["enabled": enabled ? "1" : "0"])
    }

    @objc private func openSettings() {
        let alert = NSAlert()
        alert.messageText = "设置"
        alert.informativeText = "这里放你自己的设置窗口。"
        alert.runModal()
    }

    @objc private func quit() {
        // 退出时告诉 Hub 一声，Hub 会把界面上的状态改成离线
        AKHubClient.shared.stop()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        AKHubClient.shared.stop()
    }
}
