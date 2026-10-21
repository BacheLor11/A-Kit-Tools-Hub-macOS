import AppKit
import AKitStatusKit

// 演示工具：证明「接入 A-Kit」和「不接入照样能跑」两件事
// 用法：先开 A-Kit，再跑这个 → 它自己的图标会消失，菜单出现在 A-Kit 里
//      关掉 A-Kit → 它 5 秒内自己把图标挂回来

final class DemoDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var muted = false
    private var greetCount = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "D"
        rebuildOwnMenu()

        AKHubClient.shared.onConnectionChange = { [weak self] connected in
            guard let self else { return }
            // 关键：只有连上 Hub 才让出图标；Hub 没了立刻拿回来
            self.statusItem.isVisible = !connected
            print(connected ? "✓ 已接入 A-Kit，自己的图标已隐藏" : "· 未连接 A-Kit，使用自己的图标")
        }

        AKHubClient.shared.onInvoke = { [weak self] itemId in
            self?.handle(itemId)
        }

        AKHubClient.shared.onEvent = { name, payload in
            print("收到事件 \(name) \(payload)")
        }

        AKHubClient.shared.start(info: AKToolInfo(
            bundleId: "com.aibao.DemoTool",
            name: "DemoTool",
            version: "0.1.0",
            status: muted ? "已静音" : "运行中",
            menu: menuModel(),
            subscribes: ["netpulse.offline"]
        ))
    }

    private func menuModel() -> [AKMenuItem] {
        [
            AKMenuItem(id: "status", title: muted ? "状态：已静音" : "状态：正常运行", kind: .header),
            .separator(),
            AKMenuItem(id: "toggleMute", title: "静音", kind: .toggle, checked: muted),
            AKMenuItem(id: "greet", title: "打个招呼", shortcut: "⌘G"),
            .separator(),
            AKMenuItem(id: "quit", title: "退出 DemoTool"),
        ]
    }

    private func handle(_ itemId: String) {
        switch itemId {
        case "toggleMute":
            muted.toggle()
            print("切换静音 → \(muted)")
        case "greet":
            greetCount += 1
            print("打招呼第 \(greetCount) 次")
        case "quit":
            NSApp.terminate(nil)
        default:
            print("未知菜单项 \(itemId)")
        }
        rebuildOwnMenu()
        AKHubClient.shared.update(menu: menuModel(), status: muted ? "已静音" : "运行中")
    }

    private func rebuildOwnMenu() {
        let menu = NSMenu()
        let head = NSMenuItem(title: muted ? "状态：已静音" : "状态：正常运行", action: nil, keyEquivalent: "")
        head.isEnabled = false
        menu.addItem(head)
        menu.addItem(.separator())
        let toggle = NSMenuItem(title: "静音", action: #selector(toggleAction), keyEquivalent: "")
        toggle.target = self
        toggle.state = muted ? .on : .off
        menu.addItem(toggle)
        let greet = NSMenuItem(title: "打个招呼", action: #selector(greetAction), keyEquivalent: "g")
        greet.target = self
        menu.addItem(greet)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleAction() { handle("toggleMute") }
    @objc private func greetAction() { handle("greet") }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = DemoDelegate()
app.delegate = delegate
app.run()
