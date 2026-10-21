import AppKit
import SwiftUI
import Carbon.HIToolbox
import AKitCore
import AKitStatusKit

@main
@MainActor
struct AKitMain {
    static func main() {
        // 开发用：--snapshot <路径> [page] 离屏渲染一张界面图
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            selfTest()
            return
        }

        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let path = args[i + 1]
            let page = (i + 2 < args.count) ? args[i + 2] : "tools"
            renderSnapshot(to: path, pageName: page)
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    /// 协议自测：起服务 → 客户端注册 → 服务端下发一次点击 → 校验客户端收到
    static func selfTest() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let server = HubServer()
        server.start()

        final class Box: @unchecked Sendable { var value: String? }
        let box = Box()

        let client = AKHubClient.shared
        client.onInvoke = { itemId in box.value = itemId }
        client.start(info: AKToolInfo(
            bundleId: "com.aibao.SelfTest", name: "SelfTest", version: "1.0",
            status: "测试中",
            menu: [AKMenuItem(id: "ping", title: "Ping")]))

        let d1 = Date().addingTimeInterval(5)
        while Date() < d1 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if !server.connectedTools.isEmpty { break }
        }
        guard let registered = server.connectedTools.first else {
            print("FAIL: 客户端没能注册上")
            exit(1)
        }
        print("PASS register: \(registered.name) v\(registered.version) items=\(registered.menu.count)")

        server.invoke(toolId: "com.aibao.SelfTest", itemId: "ping")
        let d2 = Date().addingTimeInterval(3)
        while Date() < d2 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if box.value != nil { break }
        }
        if box.value == "ping" {
            print("PASS invoke: 客户端收到 ping")
        } else {
            print("FAIL invoke: 客户端没收到回调")
            exit(1)
        }

        // 事件总线
        var gotEvent: String?
        client.onEvent = { name, _ in gotEvent = name }
        server.emit("netpulse.offline", payload: ["since": "1"])
        let d3 = Date().addingTimeInterval(2)
        while Date() < d3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if gotEvent != nil { break }
        }
        print(gotEvent == "netpulse.offline" ? "PASS event: Hub → 工具" : "FAIL event: 没收到事件")

        // 反方向：工具 → Hub
        final class HubBox: @unchecked Sendable { var value: String? }
        let hubBox = HubBox()
        server.onEvent = { name, _, from in hubBox.value = "\(name)@\(from ?? "?")" }
        client.emit("selftest.hello", payload: ["x": "1"])
        let d4 = Date().addingTimeInterval(2)
        while Date() < d4 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if hubBox.value != nil { break }
        }
        if let v = hubBox.value, v.hasPrefix("selftest.hello@") {
            print("PASS event: 工具 → Hub（\(v)）")
        } else {
            print("FAIL event: Hub 没收到工具发的事件")
            exit(1)
        }
        exit(0)
    }

    static func renderSnapshot(to path: String, pageName: String) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)
        let isPanel = pageName == "panel"
        let isImport = pageName == "import"
        let state = AppState(bootstrap: false)
        state.page = AppState.Page(rawValue: pageName) ?? .tools

        // 快照模式下可以用 AKIT_SCAN_DIRS 指定要扫的目录（冒号分隔），只影响这一次渲染
        if let dirs = ProcessInfo.processInfo.environment["AKIT_SCAN_DIRS"], !dirs.isEmpty {
            state.settings.scanDirectories = dirs.split(separator: ":").map(String.init)
            state.settings.manifestURL = ""
        }
        // 快照也要把插件带上，否则验证不到「工具自己的界面嵌进来」这条链路
        state.pluginManager.scanAndLoad()
        Task { await state.refreshAll() }

        let width: CGFloat = isPanel ? 336 : (isImport ? 640 : 1080)
        let root: AnyView = isPanel
            ? AnyView(PanelView(onOpenConsole: {}, onShowMenu: { _ in }, onQuit: {}, onSettings: {})
                .environmentObject(state)
                .frame(width: width))
            : isImport
            ? AnyView(ImportSheet().environmentObject(state).frame(width: 640, height: 540))
            : AnyView(RootView().environmentObject(state).frame(width: width, height: 720))
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: width, height: isPanel ? 200 : (isImport ? 540 : 720))
        host.layoutSubtreeIfNeeded()

        // 让异步扫描 / 清单加载跑完
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if !state.entries.isEmpty { break }
        }
        print("snapshot: \(state.manifestLabel) · \(state.entries.count) 条 · 扫 \(state.settings.scanDirectories.count) 个目录")

        if isPanel {
            let fit = host.fittingSize
            host.frame = NSRect(x: 0, y: 0, width: width, height: fit.height)
        }
        host.layoutSubtreeIfNeeded()

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            print("snapshot: 无法创建位图")
            return
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
            print("snapshot → \(path)")
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var window: NSWindow?
    /// 菜单栏代持：把配成 hubbar 的插件图标画在系统菜单栏上
    private let statusProxy = StatusItemProxy()
    private var hotKeyRef: EventHotKeyRef?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?

    // MARK: 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyDockPolicy()
        setupStatusItem()
        setupWindow()
        registerHotKey()
        observeSettingsChanges()
        bootPlugins()

        // 首次启动（没有配置文件）直接把主窗口打开
        if !FileManager.default.fileExists(atPath: AKPaths.settingsFile.path) {
            showWindow()
        }
    }

    /// 加载插件。
    ///
    /// 插件崩了宿主一起崩，所以这里必须放在所有 UI 就绪之后——
    /// 至少用户能看见面板，而不是黑屏一片。
    private func bootPlugins() {
        let pm = state.pluginManager
        pm.onOpenWindow = { [weak self] in self?.showWindow() }
        pm.onPresentFull = { [weak self] pluginId in
            guard let self else { return }
            self.hidePanel()
            self.state.selectedPluginId = pluginId
            self.state.page = .plugins
            self.showWindow()
        }

        statusProxy.onClick = { [weak self] pluginId in
            guard let self else { return }
            self.state.focusPluginId = pluginId
            if let p = self.state.pluginManager.plugin(id: pluginId) {
                self.state.selectedPluginId = p.id
            }
            self.showPanel()
        }

        state.onLayoutChanged = { [weak self] in
            self?.statusProxy.invalidate()
            self?.syncPluginBars()
        }

        pm.boot()
        syncPluginBars()
        if let notice = pm.notice {
            state.toast = AppState.Toast(text: notice, ok: false)
        }
    }

    /// 把「哪些插件要挂在系统菜单栏」同步给代持层
    private func syncPluginBars() {
        statusProxy.sync(plugins: state.pluginManager.plugins, layout: state.layout)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalClickMonitor { NSEvent.removeMonitor(globalClickMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
    }

    // MARK: 状态栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.menuBarImage()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        item.isVisible = state.settings.showMenuBarIcon
    }

    private static func menuBarImage() -> NSImage? {
        let candidates = [
            Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/MenuBarIcon.png"),
        ].compactMap { $0 }
        for url in candidates {
            if let img = NSImage(contentsOf: url) {
                img.isTemplate = true
                img.size = NSSize(width: 18, height: 18)
                return img
            }
        }
        let fallback = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "A-Kit")
        fallback?.isTemplate = true
        return fallback
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let isRight = NSApp.currentEvent?.type == .rightMouseUp
        let wantsMenu = isRight || state.layout.clickBehavior == "menu"
        if wantsMenu {
            showStatusMenu()
        } else {
            togglePanel()
        }
    }

    private func showStatusMenu() {
        guard let statusItem else { return }
        let menu = buildStatusMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // 菜单关闭后要把 menu 摘掉，否则左键也会走菜单
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let console = NSMenuItem(title: "打开控制台", action: #selector(showWindowAction), keyEquivalent: "")
        console.target = self
        menu.addItem(console)
        menu.addItem(.separator())

        let tools = state.entries.filter { $0.isInstalled && !state.layout.isHidden($0.id) }
        if tools.isEmpty {
            let none = NSMenuItem(title: "没有显示中的工具", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for entry in tools {
            let bundleId = entry.installed?.bundleId ?? entry.id
            let info = state.toolInfo(bundleId)
            let title = info?.status.map { "\(entry.name) — \($0)" } ?? entry.name
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            if let info, !info.menu.isEmpty {
                let sub = NSMenu()
                for mi in state.menuItems(for: info, action: #selector(invokeFromMenu(_:)), target: self) {
                    sub.addItem(mi)
                }
                sub.addItem(.separator())
                let open = NSMenuItem(title: "打开 \(entry.name)", action: #selector(openToolFromMenu(_:)), keyEquivalent: "")
                open.target = self
                open.representedObject = bundleId
                sub.addItem(open)
                item.submenu = sub
            } else {
                item.action = #selector(openToolFromMenu(_:))
                item.target = self
                item.representedObject = bundleId
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let upd = NSMenuItem(title: state.updates.isEmpty ? "检查更新" : "有 \(state.updates.count) 个更新",
                             action: #selector(checkUpdatesAction), keyEquivalent: "")
        upd.target = self
        menu.addItem(upd)
        let settings = NSMenuItem(title: "设置…", action: #selector(showSettingsAction), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 A-Kit", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func invokeFromMenu(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        state.invoke(toolId: pair[0], itemId: pair[1])
    }

    @objc private func openToolFromMenu(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String,
              let entry = state.entries.first(where: { ($0.installed?.bundleId ?? $0.id) == bundleId }) else { return }
        state.open(entry)
    }

    @objc private func checkUpdatesAction() {
        Task { await state.checkUpdates(silent: false) }
    }

    @objc private func showSettingsAction() {
        state.page = .settings
        showWindow()
    }

    @objc private func showWindowAction() {
        showWindow()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: 面板

    private func makePanel() -> NSPanel {
        let view = PanelView(
            onOpenConsole: { [weak self] in
                self?.hidePanel()
                self?.showWindow()
            },
            onShowMenu: { [weak self] bundleId in
                self?.popMenu(for: bundleId)
            },
            onQuit: { NSApp.terminate(nil) },
            onSettings: { [weak self] in
                self?.hidePanel()
                self?.state.page = .settings
                self?.showWindow()
            }
        )
        .environmentObject(state)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 336, height: 200)
        host.layoutSubtreeIfNeeded()
        let height = min(max(host.fittingSize.height, 120), 580)

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 336, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        host.frame = NSRect(x: 0, y: 0, width: 336, height: height)
        p.contentView = host
        return p
    }

    /// 工具数量变化时重新贴合内容高度
    private func resizePanelToFit(_ p: NSPanel) {
        guard let host = p.contentView else { return }
        host.frame = NSRect(x: 0, y: 0, width: 336, height: 200)
        host.layoutSubtreeIfNeeded()
        let height = min(max(host.fittingSize.height, 120), 580)
        var frame = p.frame
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        p.setFrame(frame, display: true)
        host.frame = NSRect(x: 0, y: 0, width: 336, height: height)
    }

    private func togglePanel() {
        if let p = panel, p.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        // 面板打开时顺手对齐一次菜单栏代持状态（有签名缓存，不会闪）
        syncPluginBars()
        if panel == nil { panel = makePanel() }
        guard let p = panel else { return }
        resizePanelToFit(p)
        positionPanel(p)
        p.orderFrontRegardless()
        p.makeKey()
        installClickMonitor()
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        if let m = globalClickMonitor { NSEvent.removeMonitor(m); globalClickMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
    }

    private func positionPanel(_ p: NSPanel) {
        let size = p.frame.size
        var origin = NSPoint.zero
        if let button = statusItem?.button, let win = button.window {
            let rect = win.convertToScreen(button.convert(button.bounds, to: nil))
            origin = NSPoint(x: rect.midX - size.width / 2, y: rect.minY - size.height - 6)
        } else if let screen = NSScreen.main {
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height - 40)
        }
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            origin.x = max(visible.minX + 8, min(origin.x, visible.maxX - size.width - 8))
            origin.y = max(visible.minY + 8, origin.y)
        }
        p.setFrameOrigin(origin)
    }

    private func installClickMonitor() {
        if globalClickMonitor == nil {
            globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                self?.hidePanel()
            }
        }
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                if event.keyCode == 53 { self?.hidePanel(); return nil }
                return event
            }
        }
    }

    /// 弹出某个工具的原生菜单（面板里的「⋯」）
    private func popMenu(for bundleId: String) {
        guard let info = state.toolInfo(bundleId) else { return }
        let menu = NSMenu()
        for mi in state.menuItems(for: info, action: #selector(invokeFromMenu(_:)), target: self) {
            menu.addItem(mi)
        }
        if menu.items.isEmpty {
            let none = NSMenuItem(title: "这个工具没有菜单项", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: 主窗口

    private func setupWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "A-Kit"
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = AKWindowColor.dynamic
        w.minSize = NSSize(width: 940, height: 620)
        w.delegate = self
        w.contentView = NSHostingView(rootView: RootView().environmentObject(state))
        w.setFrameAutosaveName("AKitMainWindow")
        w.center()
        window = w
    }

    func showWindow() {
        if window == nil { setupWindow() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 外观

    private func applyDockPolicy() {
        NSApp.setActivationPolicy(state.settings.showDockIcon ? .regular : .accessory)
    }

    private func observeSettingsChanges() {
        NotificationCenter.default.addObserver(forName: .akitMenuBarVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.statusItem?.isVisible = self?.state.settings.showMenuBarIcon ?? true
            }
        }
        NotificationCenter.default.addObserver(forName: .akitDockVisibilityChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.applyDockPolicy() }
        }
    }

    // MARK: 全局快捷键

    private func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.togglePanel() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let (keyCode, modifiers) = Self.parseHotkey(state.settings.hotkey)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x414B4954), id: 1)  // 'AKIT'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
            AKLogInfo("app", "hotkey registered \(state.settings.hotkey)")
        } else {
            AKLogInfo("app", "hotkey 注册失败 status=\(status)")
        }
    }

    static func parseHotkey(_ text: String) -> (UInt32, UInt32) {
        var keyCode = UInt32(kVK_ANSI_A)
        var modifiers: UInt32 = 0
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            switch part {
            case "cmd", "command", "⌘": modifiers |= UInt32(cmdKey)
            case "shift", "⇧": modifiers |= UInt32(shiftKey)
            case "opt", "option", "alt", "⌥": modifiers |= UInt32(optionKey)
            case "ctrl", "control", "⌃": modifiers |= UInt32(controlKey)
            default:
                if let scalar = part.uppercased().unicodeScalars.first,
                   let code = keyCodes[scalar] {
                    keyCode = code
                }
            }
        }
        return (keyCode, modifiers)
    }

    private static let keyCodes: [Unicode.Scalar: UInt32] = {
        var map: [Unicode.Scalar: UInt32] = [:]
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let letterCodes: [UInt32] = [
            UInt32(kVK_ANSI_A), UInt32(kVK_ANSI_B), UInt32(kVK_ANSI_C), UInt32(kVK_ANSI_D),
            UInt32(kVK_ANSI_E), UInt32(kVK_ANSI_F), UInt32(kVK_ANSI_G), UInt32(kVK_ANSI_H),
            UInt32(kVK_ANSI_I), UInt32(kVK_ANSI_J), UInt32(kVK_ANSI_K), UInt32(kVK_ANSI_L),
            UInt32(kVK_ANSI_M), UInt32(kVK_ANSI_N), UInt32(kVK_ANSI_O), UInt32(kVK_ANSI_P),
            UInt32(kVK_ANSI_Q), UInt32(kVK_ANSI_R), UInt32(kVK_ANSI_S), UInt32(kVK_ANSI_T),
            UInt32(kVK_ANSI_U), UInt32(kVK_ANSI_V), UInt32(kVK_ANSI_W), UInt32(kVK_ANSI_X),
            UInt32(kVK_ANSI_Y), UInt32(kVK_ANSI_Z),
        ]
        for (i, ch) in letters.enumerated() {
            map[ch.unicodeScalars.first!] = letterCodes[i]
        }
        let digits: [UInt32] = [UInt32(kVK_ANSI_0), UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2),
                                UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5),
                                UInt32(kVK_ANSI_6), UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8),
                                UInt32(kVK_ANSI_9)]
        for (i, code) in digits.enumerated() {
            map[Unicode.Scalar(UInt8(48 + i))] = code
        }
        map[" "] = UInt32(kVK_Space)
        return map
    }()
}
