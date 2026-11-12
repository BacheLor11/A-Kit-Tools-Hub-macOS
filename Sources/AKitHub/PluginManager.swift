import Foundation
import AppKit
import SwiftUI
import Combine
import AKitCore
import AKitPluginKit
import AKitHostKit

// MARK: - 已加载的插件

@MainActor
final class LoadedPlugin: ObservableObject, Identifiable {
    nonisolated var id: String { record.id }

    let record: AKPluginRecord
    let descriptor: AKPluginDescriptor
    /// 插件宿主 app 的 bundleId（插件住在 `Xxx.app/Contents/PlugIns/` 里时才有）。
    ///
    /// 只算一次：运行态仲裁要反复比对「这个 app 现在跑没跑」，
    /// 每次都去 `Bundle(url:)` 太浪费，也容易在 app 被替换的瞬间读到半截。
    let hostBundleId: String?

    /// 插件自己推的一行状态（折叠态显示）
    @Published var statusText: String?
    /// 加载 / 运行错误
    @Published var error: String?
    /// 非空表示插件虽然加载了，但被让位了（比如工具正独立运行着）
    @Published var inactiveReason: String?
    /// 面板视图是否已创建（懒加载，插件多时不拖慢启动）
    @Published private(set) var materialized = false

    var isActive: Bool { inactiveReason == nil }

    private var _panelView: NSView?
    private var _fullView: NSView?

    init(record: AKPluginRecord, descriptor: AKPluginDescriptor) {
        self.record = record
        self.descriptor = descriptor
        self.statusText = descriptor.statusText()
        self.hostBundleId = record.appPath.flatMap {
            Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier
        }
    }

    /// 窄界面（面板里的卡片）。同一个工具只创建一次，之后复用。
    func panelView(width: CGFloat) -> NSView {
        if let v = _panelView { return v }
        let v = descriptor.makePanelView(width: width)
        _panelView = v
        materialized = true
        return v
    }

    /// 宽界面（控制台里的整页）
    func fullView() -> NSView {
        if let v = _fullView { return v }
        let v = descriptor.makeFullView()
        _fullView = v
        return v
    }

    var icon: NSImage? { descriptor.statusItemImage() }
}

// MARK: - 宿主代理

/// 每个插件一个代理，这样插件回调时宿主知道「是谁在说话」。
///
/// 必须继承 NSObject：`AKPluginHost` 是 `@objc` 协议，走 ObjC runtime 才能跨 dylib 匹配。
/// 不标 `@MainActor`：ObjC 调用方（插件）可能在任意线程，方法内部一律 hop 回主线程。
final class PluginHostProxy: NSObject, AKPluginHost {
    let pluginId: String
    weak var manager: PluginManager?

    init(pluginId: String, manager: PluginManager) {
        self.pluginId = pluginId
        self.manager = manager
    }

    func requestLayoutRefresh() {
        let id = pluginId
        Task { @MainActor [weak self] in self?.manager?.noteLayoutChanged(pluginId: id) }
    }

    func setStatusText(_ text: String?) {
        let id = pluginId
        Task { @MainActor [weak self] in self?.manager?.noteStatus(pluginId: id, text: text) }
    }

    func setStatusItemImage(_ image: NSImage?) {
        let id = pluginId
        Task { @MainActor [weak self] in self?.manager?.noteIconChanged(pluginId: id) }
    }

    func presentFullPanel(_ pluginId: String) {
        let id = pluginId
        Task { @MainActor [weak self] in self?.manager?.requestPresentFull(id) }
    }

    func openWindow() {
        Task { @MainActor [weak self] in self?.manager?.requestOpenWindow() }
    }

    func emit(_ event: String, payload: [String: String]?) {
        let id = pluginId
        Task { @MainActor [weak self] in
            self?.manager?.relay(pluginId: id, event: event, payload: payload)
        }
    }

    func log(_ message: String) {
        AKLogInfo("plugin:\(pluginId)", message)
    }
}

// MARK: - 插件管理器

/// 扫描、加载、仲裁、记住谁被禁用了。
@MainActor
final class PluginManager: NSObject, ObservableObject {

    @Published private(set) var plugins: [LoadedPlugin] = []
    /// 加载失败的插件（保留下来，让用户看见问题而不是静默消失）
    @Published private(set) var failures: [(url: URL, message: String)] = []
    /// 一次性提示（比如「上次崩在 X，已禁用」）
    @Published var notice: String?

    /// 宿主回调：打开某个工具的完整界面
    var onPresentFull: ((String) -> Void)?
    /// 宿主回调：打开主窗口
    var onOpenWindow: (() -> Void)?
    /// 事件转发（接到老的 socket 事件总线）
    var onRelayEvent: ((String, String, [String: String]?) -> Void)?

    private let loader = AKPluginLoader()
    private let sentinel: AKCrashSentinel
    private var disabled: Set<String> = []
    private var handles: [String: UnsafeMutableRawPointer] = [:]
    private var booted = false
    /// 独立 app 启停的监听。插件和 app 是同一份工具的两种活法，
    /// 谁在跑必须随时对齐 —— 只在启动时判断一次，用户中途打开 app 就会出现两份实例。
    private var workspaceObservers: [NSObjectProtocol] = []
    /// 上次异常退出时正在加载的插件
    private(set) var crashSuspects: [String] = []

    override init() {
        sentinel = AKCrashSentinel(url: AKPaths.crashSentinel)
        super.init()
        // 时序很重要：先读嫌疑，再 begin() 覆盖
        crashSuspects = sentinel.suspects
        loadDisabled()
    }

    // MARK: 启动

    func boot() {
        guard !booted else {
            AKLogInfo("plugin", "boot 被重复调用，跳过")
            return
        }
        booted = true
        AKLogInfo("plugin", "boot 开始，插件目录 \(AKPaths.plugins.path)")

        if !crashSuspects.isEmpty {
            for id in crashSuspects { disabled.insert(id) }
            saveDisabled()
            notice = "上次退出时「\(crashSuspects.joined(separator: "、"))」加载失败导致崩溃，已自动禁用。可在设置里重新启用。"
            AKLogInfo("plugin", "崩溃哨兵：禁用 \(crashSuspects)")
        }

        sentinel.begin()
        observeAppLifecycle()
        scanAndLoad()
    }

    /// 正常退出时调用（清掉哨兵）
    func shutdown() {
        for p in plugins { p.descriptor.deactivate() }
        sentinel.clear()
        let nc = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers { nc.removeObserver(token) }
        workspaceObservers.removeAll()
    }

    /// 重新扫描。用于装/卸插件之后。
    ///
    /// 已经 dlopen 的插件不 `dlclose`（它的 NSView 可能还挂在那儿），
    /// 只做「清列表 → 重新加载」，同一路径 dlopen 会复用已有句柄。
    func reload() {
        for p in plugins { p.descriptor.deactivate() }
        plugins.removeAll()
        handles.removeAll()
        scanAndLoad()
    }

    // MARK: 扫描与加载

    func scanAndLoad() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: AKPaths.plugins,
                                                     includingPropertiesForKeys: nil,
                                                     options: [.skipsHiddenFiles]) else {
            AKLogInfo("plugin", "插件目录读不出来：\(AKPaths.plugins.path)")
            return
        }
        AKLogInfo("plugin", "扫描到 \(items.count) 个条目")

        failures.removeAll()
        for url in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard url.pathExtension == "akitplugin" else { continue }

            // 软链悬空 = 宿主 app 被删了，直接清掉
            if !fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
                AKLogInfo("plugin", "清理悬空软链 \(url.lastPathComponent)")
                continue
            }

            do {
                let record = try loader.readRecord(at: url)
                if plugins.contains(where: { $0.record.id == record.id }) { continue }
                if disabled.contains(record.id) { continue }

                sentinel.willLoad(record.id)
                let host = PluginHostProxy(pluginId: record.id, manager: self)
                let loaded = try loader.load(record: record, host: host)
                sentinel.didLoad(record.id)

                handles[record.id] = loaded.handle
                let plugin = LoadedPlugin(record: loaded.record, descriptor: loaded.descriptor)

                // 单实例仲裁：工具的独立 app 正在跑，插件就让位。
                // 两个实例各跑一份引擎、同时清理同一块磁盘，那是数据安全问题。
                let appIsRunning = plugin.hostBundleId.map { Scanner.isRunning(bundleId: $0) } ?? false
                if appIsRunning {
                    plugin.inactiveReason = "\(record.displayName) 正在独立运行"
                    AKLogInfo("plugin", "\(record.displayName) 独立运行中，插件让位")
                }

                plugins.append(plugin)
                if !appIsRunning { loaded.descriptor.activate() }
                AKLogInfo("plugin", "已加载 \(record.displayName) v\(record.version)（ABI \(record.abiVersion)）")
            } catch {
                failures.append((url, error.localizedDescription))
                AKLogInfo("plugin", "加载失败 \(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        objectWillChange.send()
    }

    // MARK: 运行态仲裁（插件 ↔ 独立 app）

    /// 按宿主 bundleId 找插件（插件 id 与宿主 bundleId 都算，兼容不守约定的插件）
    func plugin(forHostBundleId bundleId: String) -> LoadedPlugin? {
        plugins.first { $0.record.id == bundleId || $0.hostBundleId == bundleId }
    }

    /// 监听独立 app 的启停。
    ///
    /// 以前只在加载插件的那一刻判断「app 是不是在跑」，之后就不再管了：
    /// 用户从 Dock / Finder 打开 app，或者 A-Kit 自己把 app 拉起来，
    /// 插件仍然在 A-Kit 进程里跑 —— 两份实例同时改同一份数据。
    private func observeAppLifecycle() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let token = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleId = app.bundleIdentifier else { return }
                Task { @MainActor [weak self] in self?.syncArbitration(bundleId: bundleId) }
            }
            workspaceObservers.append(token)
        }
    }

    /// 把某个 app 的启停同步到它的插件上：app 起来插件立刻让位，app 退出去插件接回来。
    ///
    /// 只动「因为独立运行而让位」的那一类；用户手动禁用 / 接管失败的不碰。
    func syncArbitration(bundleId: String) {
        let running = Scanner.isRunning(bundleId: bundleId)
        var changed = false
        for p in plugins where p.hostBundleId == bundleId {
            if running, p.isActive {
                p.descriptor.deactivate()
                p.inactiveReason = "\(p.record.displayName) 正在独立运行"
                // 工具已经在外面跑起来了，A-Kit 里那扇窗再留着就是两份界面
                PluginWindows.shared.close(p.id)
                changed = true
                AKLogInfo("plugin", "\(p.record.displayName) 的独立 app 启动了，插件让位")
            } else if !running, !p.isActive, p.inactiveReason?.hasSuffix("正在独立运行") == true {
                p.inactiveReason = nil
                p.descriptor.activate()
                changed = true
                AKLogInfo("plugin", "\(p.record.displayName) 的独立 app 已退出，插件接回")
            }
        }
        if changed { objectWillChange.send() }
    }

    /// A-Kit 自己要把工具以独立 app 跑起来之前调一次。
    ///
    /// 插件是 dlopen 在 A-Kit 进程里的，没法真的卸载；只能先 `deactivate()`
    /// 停掉它的引擎并标记让位，等 app 退出后由 `syncArbitration` 接回来。
    func yieldToStandalone(_ pluginId: String) {
        guard let p = plugin(id: pluginId), p.isActive else { return }
        p.descriptor.deactivate()
        p.inactiveReason = "\(p.record.displayName) 正在独立运行"
        PluginWindows.shared.close(p.id)
        objectWillChange.send()
        AKLogInfo("plugin", "\(p.record.displayName) 让位给独立 app")
    }

    // MARK: 启用 / 禁用

    /// 移除结果：`ok=false` 时界面给红色提示，别假装成功
    struct RemoveResult {
        var ok: Bool
        var message: String
    }

    /// 把一个插件移出 A-Kit。
    ///
    /// 只动 A-Kit 自己的 Plugins 目录里的那一条（通常是软链）：
    /// - 软链 → 移到废纸篓，工具本体完全不动，重装工具后还能再接回来
    /// - 实目录 → 移到废纸篓
    ///
    /// dlopen 过的代码不能真的 unload（它的 NSView 还活着），所以同时写进
    /// `disabled`：本次运行不再出现，下次启动也不会再加载。
    @discardableResult
    func remove(pluginId: String) -> RemoveResult {
        guard let p = plugin(id: pluginId) else {
            return RemoveResult(ok: false, message: "这个插件已经不在了")
        }
        let fm = FileManager.default
        var detail: String

        if let entry = entryURL(for: p.record) {
            let isLink = (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
            var trashed: NSURL?
            do {
                try fm.trashItem(at: entry, resultingItemURL: &trashed)
                detail = isLink ? "软链已移到废纸篓，工具本体没动" : "插件包已移到废纸篓"
            } catch {
                // 废纸篓不可用（外置卷 / 权限）时：软链可以安全断开，实目录绝不硬删
                if isLink, (try? fm.removeItem(at: entry)) != nil {
                    detail = "软链已断开，工具本体没动"
                } else {
                    AKLogInfo("plugin", "移除 \(pluginId) 失败：\(error.localizedDescription)")
                    return RemoveResult(ok: false, message: "移除失败：\(error.localizedDescription)")
                }
            }
        } else {
            detail = "没找到插件文件，只做了禁用"
        }

        disabled.insert(pluginId)
        saveDisabled()
        p.descriptor.deactivate()
        plugins.removeAll { $0.record.id == pluginId }
        objectWillChange.send()
        AKLogInfo("plugin", "已移出 \(p.record.displayName)（\(detail)）")
        return RemoveResult(ok: true, message: "已移出 A-Kit · \(p.record.displayName)（\(detail)）")
    }

    /// 插件在 Plugins 目录里的那一条（软链本身，不是解析后的真实路径）。
    private func entryURL(for record: AKPluginRecord) -> URL? {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: AKPaths.plugins,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) else { return nil }
        let target = URL(fileURLWithPath: record.bundlePath).standardizedFileURL.path
        for item in items where item.pathExtension == "akitplugin" {
            if item.resolvingSymlinksInPath().standardizedFileURL.path == target { return item }
        }
        let name = URL(fileURLWithPath: record.bundlePath).lastPathComponent
        return items.first { $0.lastPathComponent == name }
    }

    func isDisabled(_ pluginId: String) -> Bool { disabled.contains(pluginId) }

    /// 工具正在独立运行时，用户点「接管」。
    ///
    /// 流程是协商而不是硬抢：请它优雅退出（保存状态）→ 等它真的退 → 插件才激活。
    func takeOver(pluginId: String) {
        guard let p = plugin(id: pluginId),
              let appPath = p.record.appPath,
              let bundle = Bundle(url: URL(fileURLWithPath: appPath)),
              let bundleId = bundle.bundleIdentifier,
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
        else { return }

        AKLogInfo("plugin", "接管 \(pluginId)：请求 \(bundleId) 退出")
        app.terminate()

        Task { @MainActor in
            for _ in 0..<24 {
                try? await Task.sleep(nanoseconds: 150_000_000)
                if !Scanner.isRunning(bundleId: bundleId) { break }
            }
            if Scanner.isRunning(bundleId: bundleId) {
                p.inactiveReason = "它没有退出，可能正在执行任务"
            } else if !p.isActive {
                // 退出通知可能已经把它接回来了，别 activate 第二遍
                p.inactiveReason = nil
                p.descriptor.activate()
                AKLogInfo("plugin", "接管 \(pluginId) 完成")
            }
            objectWillChange.send()
        }
    }

    /// 禁用需要重启 A-Kit —— dlopen 之后不能安全卸载（插件的 NSView 还活着）
    func disable(_ pluginId: String) {
        disabled.insert(pluginId)
        saveDisabled()
        notice = "已禁用。重启 A-Kit 后生效。"
    }

    func enable(_ pluginId: String) {
        disabled.remove(pluginId)
        saveDisabled()
        notice = "已启用。重启 A-Kit 后生效。"
    }

    private func loadDisabled() {
        guard let data = try? Data(contentsOf: AKPaths.pluginStateFile),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["disabled"] as? [String] else { return }
        disabled = Set(list)
    }

    private func saveDisabled() {
        let obj: [String: Any] = ["disabled": Array(disabled).sorted()]
        guard let data = try? JSONSerialization.data(withJSONObject: obj,
                                                     options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: AKPaths.pluginStateFile, options: .atomic)
    }

    // MARK: 宿主回调

    func noteLayoutChanged(pluginId: String) {
        objectWillChange.send()
    }

    func noteStatus(pluginId: String, text: String?) {
        plugins.first { $0.record.id == pluginId }?.statusText = text
    }

    func noteIconChanged(pluginId: String) {
        objectWillChange.send()
    }

    func requestPresentFull(_ pluginId: String) {
        onPresentFull?(pluginId)
    }

    func requestOpenWindow() {
        onOpenWindow?()
    }

    func relay(pluginId: String, event: String, payload: [String: String]?) {
        onRelayEvent?(pluginId, event, payload)
    }

    func plugin(id: String) -> LoadedPlugin? {
        plugins.first { $0.record.id == id }
    }

    /// 把事件广播给所有插件（来自老协议工具或插件自己）。
    ///
    /// `from` 用来避免回声：谁发的就不回给谁。
    func broadcast(name: String, payload: [String: String], from: String?) {
        for p in plugins where p.record.id != from {
            p.descriptor.handleEvent?(name, payload: payload)
        }
    }
}
