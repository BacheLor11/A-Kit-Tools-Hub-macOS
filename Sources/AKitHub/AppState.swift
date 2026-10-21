import Foundation
import SwiftUI
import AppKit
import Combine
import AKitCore
import AKitStatusKit
import AKitHostKit

@MainActor
final class AppState: ObservableObject {

    enum Page: String, CaseIterable, Identifiable {
        case tools, plugins, updates, menuBar, thirdParty, settings
        var id: String { rawValue }
        var title: String {
            switch self {
            case .tools: return "工具"
            case .plugins: return "插件"
            case .updates: return "更新"
            case .menuBar: return "菜单栏"
            case .thirdParty: return "第三方"
            case .settings: return "设置"
            }
        }
        var symbol: String {
            switch self {
            case .tools: return "square.grid.2x2"
            case .plugins: return "puzzlepiece.extension"
            case .updates: return "arrow.triangle.2.circlepath"
            case .menuBar: return "menubar.rectangle"
            case .thirdParty: return "app.badge.checkmark"
            case .settings: return "slider.horizontal.3"
            }
        }
    }

    struct Job: Equatable {
        var title: String
        var detail: String
        var progress: Double?
    }

    struct Toast: Equatable {
        var text: String
        var ok: Bool
        var id = UUID()
    }

    // MARK: 状态

    @Published var page: Page = .tools
    @Published var settings: AKSettings
    @Published var layout: AKLayout
    @Published var entries: [ToolEntry] = []
    /// 只通过 SDK 接进来、清单与扫描都没收录的工具（兜底卡片）
    @Published var runtimeEntries: [ToolEntry] = []
    @Published var connected: [String: AKToolInfo] = [:]
    @Published var query: String = ""
    @Published var health: [String: HealthReport] = [:]
    @Published var sizes: [String: Int64] = [:]
    @Published var usage: AKUsage
    @Published var job: Job?
    @Published var toast: Toast?
    @Published var manifestLabel: String = "尚未加载"
    @Published var lastRefresh: Date?
    @Published var selectedId: String?
    /// 控制台里正在看哪个插件的完整界面
    @Published var selectedPluginId: String?
    /// 点了菜单栏上某个插件的图标 —— 面板要展开它
    @Published var focusPluginId: String?
    /// 落点 / 排布变了，需要重建菜单栏代持
    var onLayoutChanged: (() -> Void)?
    @Published var listening = false

    // GitHub 安装
    @Published var imported: [ImportedTool] = []
    @Published var importCandidate: ImportCandidate?
    @Published var importError: String?
    @Published var parsing = false
    @Published var showImportSheet = false
    @Published var lastImportCheck: Date?

    // Dev 热重载
    @Published var watching: [String] = []
    @Published var lastBuild: [String: String] = [:]

    private var manifest: Manifest?
    /// 本机私有登记（tools.local.json），不进仓库、不在任何远端清单里
    private var localTools: [ToolSpec] = []
    private let server = HubServer()
    private var watcher: DevWatcher?
    /// 插件宿主：扫描 Plugins/、dlopen、崩溃哨兵
    let pluginManager = PluginManager()
    private var cancellables = Set<AnyCancellable>()

    // MARK: 初始化

    init(bootstrap: Bool = true) {
        AKPaths.ensure()
        settings = AKSettings.load()
        layout = AKLayout.load()
        usage = AKUsage.load()
        imported = ImportedStore.load()
        localTools = ManifestStore.loadLocal()
        ManifestStore.ensureLocalSkeleton()

        server.onClientsChanged = { [weak self] in
            DispatchQueue.main.async { self?.syncConnected() }
        }
        server.onStatusChanged = { [weak self] bundleId, status in
            DispatchQueue.main.async {
                // 只改这一个键，不重建整本字典：高频刷新时界面不抖
                guard let self, var info = self.connected[bundleId] else { return }
                info.status = status
                self.connected[bundleId] = info
            }
        }
        server.start()
        listening = server.isListening
        AKLogInfo("app", "A-Kit 启动，socket \(AKPaths.socket.path)")

        // 插件状态变了要让整个 UI 跟着刷（嵌套 ObservableObject 不会自动冒泡）
        pluginManager.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        // 事件总线：插件 ↔ 老协议工具互通
        pluginManager.onRelayEvent = { [weak self] from, name, payload in
            self?.server.emit(name, payload: payload ?? [:])
            // 也回给自己以外的插件
            self?.pluginManager.broadcast(name: name, payload: payload ?? [:], from: from)
        }
        server.onEvent = { [weak self] name, payload, from in
            self?.pluginManager.broadcast(name: name, payload: payload, from: from)
        }

        guard bootstrap else { return }
        Task {
            await loadManifest()
            await rescan()
            if settings.autoCheckUpdates {
                await checkUpdates(silent: true)
                await checkGitHubUpdates(silent: true)
            }
            startDevWatchIfNeeded()
        }
    }

    // MARK: 清单合并（远端 + 本机私有登记 + 从 GitHub 装的）
    //
    // 三条来源分开存、合并着用，谁都不污染谁：
    //   · 远端清单  → A-Kit 自己的版本信息（自更新），fork 者可换
    //   · tools.local.json → 只在这台机器上成立的东西（本地源码、私货）
    //   · imported.json   → 粘网址装进来的，带来源，能继续查更新
    // 三者都当成「清单的一部分」，后面安装/更新/体检走完全一样的流程。

    var effectiveManifest: Manifest? {
        var tools = manifest?.tools ?? []

        // 本机私有登记：同 id 覆盖，新的追加
        for local in localTools {
            if let i = tools.firstIndex(where: { $0.id == local.id }) { tools[i] = local }
            else { tools.append(local) }
        }

        let existing = Set(tools.map(\.id))
        let extra = imported.filter { !existing.contains($0.id) }.map { $0.spec() }
        if tools.isEmpty && extra.isEmpty { return nil }
        tools.append(contentsOf: extra)
        return Manifest(schemaVersion: 1, generatedAt: manifest?.generatedAt, tools: tools)
    }

    var importedIds: Set<String> { Set(imported.map(\.id)) }

    func isImported(_ entry: ToolEntry) -> Bool { importedIds.contains(entry.id) }

    func sourceLabel(_ entry: ToolEntry) -> String? {
        if let t = imported.first(where: { $0.id == entry.id }) {
            return t.slug ?? "直链安装"
        }
        if let repo = entry.spec?.repo, !repo.isEmpty { return repo }
        return nil
    }

    // MARK: 数据

    // 面板 / 列表以前只渲染 entries（清单 ∩ 扫描）。第三方工具按 SDK 接进来后，
    // 只要没装进扫描目录、或者没写进任何清单，就一张卡都没有 ——
    // 而它自己的菜单栏图标此时已经让给了 A-Kit，结果是入口彻底消失。
    // runtimeEntries 把「注册了但没被收录」的工具补成临时条目：能点开、能调菜单、能登记。

    /// 清单 + 扫描结果 + 运行时兜底，界面统一看这个
    var allEntries: [ToolEntry] { entries + runtimeEntries }

    /// **唯一真相**：安装层 + 运行层合并后的工具列表。
    ///
    /// 面板、工具页、详情页都应该读这个，不要再分别读 `entries` / `pluginManager.plugins`，
    /// 否则同一个工具会在两处各出现一次、版本还对不上。
    var entities: [ToolEntity] {
        ToolEntityIndex.merge(
            entries: allEntries,
            plugins: pluginManager.plugins,
            connected: connected,
            isDisabled: { [weak self] id in self?.pluginManager.isDisabled(id) ?? false }
        )
    }

    func entity(_ id: String) -> ToolEntity? {
        entities.first { $0.id == id }
    }

    var filtered: [ToolEntry] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return allEntries }
        let q = query.lowercased()
        return allEntries.filter {
            $0.name.lowercased().contains(q) || $0.id.lowercased().contains(q)
                || ($0.spec?.tagline ?? "").lowercased().contains(q)
        }
    }

    var updates: [ToolEntry] { entries.filter { $0.updateAvailable } }

    var installedCount: Int { allEntries.filter { $0.isInstalled }.count }

    func entry(_ id: String) -> ToolEntry? { allEntries.first { $0.id == id } }

    /// 重建运行时兜底条目。只在连接集合或扫描结果变化时调，不去碰状态刷新。
    func rebuildRuntimeEntries() {
        let known = Set(entries.compactMap { $0.installed?.bundleId ?? $0.spec?.bundleId })
        runtimeEntries = connected.values
            .filter { !known.contains($0.bundleId) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { info in
                var app: InstalledApp?
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: info.bundleId) {
                    app = Scanner.readApp(at: url)
                }
                return ToolEntry(id: info.bundleId, spec: nil, installed: app,
                                 latest: nil, runtimeName: info.name)
            }
    }

    /// 该工具是不是只靠 SDK 接入、还没被收录
    func isUnregistered(_ bundleId: String) -> Bool {
        runtimeEntries.contains { $0.id == bundleId }
    }

    /// 把运行时工具正式登记进本机清单，下次启动也认得
    func registerTool(bundleId: String) {
        guard let info = connected[bundleId] else { return }
        let spec = ToolSpec(id: Self.slug(from: info.bundleId, fallback: info.name),
                            name: info.name,
                            bundleId: info.bundleId,
                            category: "tool",
                            statusBar: StatusBarSpec(supported: true),
                            channels: ["stable": ChannelSpec(version: info.version)])
        if ManifestStore.registerLocal(spec) {
            AKLogInfo("manifest", "登记本机工具 \(info.name) (\(info.bundleId))")
            showToast("已登记 \(info.name)", ok: true)
            Task {
                await loadManifest()
                await rescan()
            }
        } else {
            showToast("登记失败，检查 tools.local.json 的权限", ok: false)
        }
    }

    /// bundleId 尾段 → 合法 id（com.aibao.ASweep → asweep）
    static func slug(from bundleId: String, fallback: String) -> String {
        let base = bundleId.split(separator: ".").last.map(String.init) ?? fallback
        let cleaned = base.lowercased().map { ch -> Character in
            (ch.isLetter || ch.isNumber) ? ch : "-"
        }
        let s = String(cleaned).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "tool-\(abs(bundleId.hashValue) % 10000)" : s
    }

    func isConnected(_ entry: ToolEntry) -> Bool {
        connected[entry.installed?.bundleId ?? entry.spec?.bundleId ?? entry.id] != nil
    }

    func statusText(_ entry: ToolEntry) -> String? {
        let key = entry.installed?.bundleId ?? entry.spec?.bundleId ?? entry.id
        if let info = connected[key], let s = info.status, !s.isEmpty { return s }
        if let days = usage.daysSinceOpened(entry.id) {
            if days == 0 { return "今天用过" }
            if days > 90 { return "\(days) 天没打开过" }
        }
        return nil
    }

    // MARK: 载入

    func loadManifest() async {
        localTools = ManifestStore.loadLocal()

        func label(_ base: String, _ count: Int) -> String {
            localTools.isEmpty ? "\(base) · \(count) 个工具"
                               : "\(base) · \(count) 个工具 + 本机 \(localTools.count)"
        }

        if !settings.manifestURL.isEmpty {
            do {
                let m = try await ManifestStore.loadRemote(settings.manifestURL)
                manifest = m
                manifestLabel = label("远程清单", m.tools.count)
                return
            } catch {
                AKLogInfo("manifest", "远程失败：\(error.localizedDescription)")
            }
        }
        if let cached = ManifestStore.loadCache() {
            manifest = cached
            manifestLabel = label("本地缓存", cached.tools.count)
            return
        }
        if let bundled = ManifestStore.loadBundled() {
            manifest = bundled
            manifestLabel = label("内置清单", bundled.tools.count)
            return
        }
        manifest = nil
        manifestLabel = localTools.isEmpty ? "没有可用清单" : "只有本机登记"
    }

    func rescan() async {
        let settings = self.settings
        imported = ImportedStore.load()
        localTools = ManifestStore.loadLocal()
        let m = effectiveManifest
        var known = Set((m?.tools ?? []).map(\.bundleId))
        for t in imported { known.insert(t.bundleId) }
        let apps = await Task.detached(priority: .userInitiated) {
            Scanner.scan(settings: settings, knownBundleIds: known)
        }.value
        entries = Registry.merge(manifest: m, installed: apps,
                                 channel: settings.channel, fallbackIds: [])

        // 新装 / 新登记的工具默认放进第一个分组，不然菜单栏页会一堆「未分组」
        if let first = layout.groups.first {
            var changed = false
            for e in entries where e.isInstalled {
                let assigned = layout.groups.contains { $0.items.contains(e.id) }
                if !assigned {
                    layout.assign(e.id, to: first.id)
                    changed = true
                }
            }
            if changed { layout.save() }
        }

        lastRefresh = Date()
        syncConnected()
    }

    func refreshAll() async {
        await loadManifest()
        await rescan()
        await checkUpdates(silent: true)
        await checkGitHubUpdates(silent: true)
    }

    func checkUpdates(silent: Bool) async {
        await loadManifest()
        let settings = self.settings
        imported = ImportedStore.load()
        let m = effectiveManifest
        var known = Set((m?.tools ?? []).map(\.bundleId))
        for t in imported { known.insert(t.bundleId) }
        let apps = await Task.detached(priority: .userInitiated) {
            Scanner.scan(settings: settings, knownBundleIds: known)
        }.value
        entries = Registry.merge(manifest: m, installed: apps,
                                 channel: settings.channel, fallbackIds: [])
        if !silent {
            let n = entries.filter { $0.updateAvailable }.count
            showToast(n == 0 ? "已经是最新版本" : "发现 \(n) 个更新", ok: true)
        }
    }

    private func syncConnected() {
        var map: [String: AKToolInfo] = [:]
        for t in server.connectedTools { map[t.bundleId] = t }
        connected = map
        rebuildRuntimeEntries()
        AKLogInfo("app", "connected=\(map.count) runtime=\(runtimeEntries.count)")
    }

    // MARK: GitHub 安装

    /// 解析一个链接：只读不写，结果放到 importCandidate 给界面预览
    func inspectImport(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        parsing = true
        importError = nil
        importCandidate = nil
        let token = settings.githubToken
        Task {
            do {
                let c = try await ImportResolver.inspect(text, token: token)
                importCandidate = c
                AKLogInfo("import", "resolved \(text) → \(c.assetName) \(c.version)")
            } catch {
                importError = error.localizedDescription
                AKLogInfo("import", "resolve failed: \(error.localizedDescription)")
            }
            parsing = false
        }
    }

    func confirmImport() {
        guard let c = importCandidate else { return }
        job = Job(title: "安装 \(c.name)", detail: "准备下载…")
        Task {
            do {
                let record = try await ImportInstaller.install(
                    c, into: targetDirectory(), backupRoot: AKPaths.backups) { msg in
                        Task { @MainActor in self.job?.detail = msg }
                    }
                job = nil
                importCandidate = nil
                showImportSheet = false
                imported = ImportedStore.load()
                showToast("\(record.name) 已安装", ok: true)
                await rescan()
            } catch {
                job = nil
                showToast(error.localizedDescription, ok: false)
                AKLogInfo("import", "install failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelImport() {
        importCandidate = nil
        importError = nil
        showImportSheet = false
    }

    /// 只检查从 GitHub 装的工具：拉最新 release，tag 变了就把下载地址换掉
    func checkGitHubUpdates(silent: Bool) async {
        var list = ImportedStore.load()
        guard !list.isEmpty else { return }
        let token = settings.githubToken
        var changed = false

        for i in list.indices {
            guard let owner = list[i].owner, let repo = list[i].repo else { continue }
            do {
                let rel = try await GitHubAPI.latestRelease(owner: owner, repo: repo, token: token)
                guard rel.tag != list[i].tag else { continue }
                let m = try? await GitHubAPI.toolManifest(owner: owner, repo: repo, tag: rel.tag, token: token)
                guard let asset = AssetPicker.pick(rel.assets, manifest: m) else { continue }
                list[i].tag = rel.tag
                list[i].version = ImportResolver.normalizeVersion(rel.tag)
                list[i].assetName = asset.name
                list[i].assetURL = asset.url
                changed = true
                AKLogInfo("import", "\(owner)/\(repo) 有新版本 \(rel.tag)")
            } catch {
                AKLogInfo("import", "检查 \(owner)/\(repo) 失败：\(error.localizedDescription)")
            }
        }

        lastImportCheck = Date()
        if changed {
            ImportedStore.save(list)
            imported = list
            await rescan()
            if !silent { showToast("来自 GitHub 的工具已刷新", ok: true) }
        }
    }

    /// 忘掉这个来源（不删 app）
    func forgetSource(_ entry: ToolEntry) {
        guard isImported(entry) else { return }
        ImportedStore.remove(id: entry.id)
        imported = ImportedStore.load()
        Task { await rescan() }
        showToast("已忘记 \(entry.name) 的来源，app 还在原处", ok: true)
    }

    // MARK: 安装 / 更新 / 卸载

    private func targetDirectory() -> URL {
        AKPaths.expand(settings.installDirectory)
    }

    func install(_ entry: ToolEntry, isUpdate: Bool) {
        guard let spec = entry.spec else {
            showToast("这个工具还没登记到清单里", ok: false)
            return
        }
        guard let channel = spec.channel(settings.channel), let urlString = channel.url,
              let url = URL(string: urlString) else {
            showToast("\(spec.name) 还没有配置下载源", ok: false)
            return
        }

        job = Job(title: "\(isUpdate ? "更新" : "安装") \(spec.name)", detail: "下载中…")
        Task {
            do {
                let file = try await Installer.download(
                    from: url,
                    to: AKPaths.downloads.appendingPathComponent("\(spec.id)-\(channel.version).zip"))

                if let expected = channel.sha256, !expected.isEmpty {
                    job?.detail = "校验完整性…"
                    let actual = try Installer.sha256(at: file)
                    guard actual.lowercased() == expected.lowercased() else {
                        throw InstallerError.checksumMismatch(expected: expected, actual: actual)
                    }
                }

                job?.detail = "解压…"
                let stage = AKPaths.downloads.appendingPathComponent("stage-\(spec.id)")
                let app = try Installer.unzip(file, into: stage)

                job?.detail = "安装到 \(settings.installDirectory)…"
                let backupRoot = AKPaths.backups
                let installedURL: URL
                if entry.isInstalled, let current = entry.installed, Scanner.isRunning(bundleId: current.bundleId) {
                    // 目标在跑：先落到临时位置，再交给延迟脚本替换
                    let staged = try Installer.install(app, into: stage.appendingPathComponent("final"),
                                                       backupTo: backupRoot, expectedBundleId: spec.bundleId)
                    try Installer.replaceWhileRunning(newApp: staged, target: current.path, relaunch: true)
                    installedURL = current.path
                } else {
                    installedURL = try Installer.install(app, into: targetDirectory(),
                                                         backupTo: backupRoot.appendingPathComponent(spec.name),
                                                         expectedBundleId: spec.bundleId)
                }
                Installer.pruneBackups(for: spec.name, root: backupRoot, keep: settings.keepBackups)
                try? FileManager.default.removeItem(at: stage)
                try? FileManager.default.removeItem(at: file)

                AKLogInfo("install", "\(spec.name) -> \(installedURL.path)")
                job = nil
                showToast("\(spec.name) \(isUpdate ? "已更新到" : "已安装") \(channel.version)", ok: true)
                await rescan()
                afterInstall(installedURL)
            } catch {
                job = nil
                AKLogInfo("install", "失败：\(error.localizedDescription)")
                showToast(error.localizedDescription, ok: false)
            }
        }
    }

    func uninstall(_ entry: ToolEntry, alsoSupportFiles: Bool) {
        guard let app = entry.installed else { return }
        let appURL = app.path
        do {
            try Installer.uninstall(appURL, bundleId: app.bundleId, alsoSupportFiles: alsoSupportFiles)
            afterUninstall(appURL)
            showToast("\(entry.name) 已移到废纸篓", ok: true)
            Task { await rescan() }
        } catch {
            showToast("卸载失败：\(error.localizedDescription)", ok: false)
        }
    }

    // MARK: 插件随安装 / 卸载

    /// 工具装好后，把包里的 `.akitplugin` 软链进 A-Kit 的插件目录。
    ///
    /// 软链而不是拷贝：app 更新时插件自动跟着更新，不会出现版本错位。
    private func afterInstall(_ appURL: URL) {
        do {
            let links = try PluginInstallBridge.link(from: appURL, into: AKPaths.plugins)
            guard !links.isEmpty else { return }
            AKLogInfo("plugin", "\(appURL.lastPathComponent) 带来 \(links.count) 个插件")
            pluginManager.reload()
            onLayoutChanged?()
        } catch {
            AKLogInfo("plugin", "插件注册失败：\(error.localizedDescription)")
        }
    }

    private func afterUninstall(_ appURL: URL) {
        let removed = PluginInstallBridge.unlink(for: appURL, in: AKPaths.plugins)
        guard !removed.isEmpty else { return }
        AKLogInfo("plugin", "卸载 \(appURL.lastPathComponent)，拔掉 \(removed.count) 个插件")
        pluginManager.reload()
        onLayoutChanged?()
    }

    /// 从源码重建并覆盖安装（Dev 模式）
    func rebuild(_ entry: ToolEntry) {
        guard let spec = entry.spec, spec.source != nil else {
            showToast("没有配置本地源码", ok: false)
            return
        }
        job = Job(title: "重建 \(spec.name)", detail: "编译中…")
        Task {
            do {
                let app = try await Task.detached(priority: .userInitiated) { () -> URL in
                    try Installer.rebuild(spec: spec) { msg in
                        AKLogInfo("dev", msg)
                    }
                }.value

                job?.detail = "安装…"
                let running = entry.installed.map { Scanner.isRunning(bundleId: $0.bundleId) } ?? false
                if running, let current = entry.installed {
                    let staged = try Installer.install(app, into: AKPaths.downloads.appendingPathComponent("stage-\(spec.id)"),
                                                       expectedBundleId: spec.bundleId)
                    try Installer.replaceWhileRunning(newApp: staged, target: current.path, relaunch: true)
                } else {
                    _ = try Installer.install(app, into: targetDirectory(),
                                              backupTo: AKPaths.backups.appendingPathComponent(spec.name),
                                              expectedBundleId: spec.bundleId)
                }
                job = nil
                showToast("\(spec.name) 已重建并安装", ok: true)
                noteBuild(entry, ok: true, text: "已安装")
                await rescan()
            } catch {
                job = nil
                noteBuild(entry, ok: false, text: String(error.localizedDescription.prefix(60)))
                showToast(error.localizedDescription, ok: false)
            }
        }
    }

    // MARK: Dev 热重载

    /// 按设置决定要不要盯源码目录
    func startDevWatchIfNeeded() {
        guard settings.devAutoRebuild else {
            watcher?.stop()
            watching = []
            return
        }
        var roots: [String: URL] = [:]
        for spec in effectiveManifest?.tools ?? [] {
            if let src = spec.source {
                roots[spec.id] = AKPaths.expand(src.path)
            }
        }
        guard !roots.isEmpty else {
            watching = []
            return
        }

        if watcher == nil {
            let w = DevWatcher()
            w.onRebuild = { [weak self] id in
                Task { @MainActor in
                    guard let self, let e = self.entry(id), e.spec?.source != nil else { return }
                    self.showToast("源码变了，重建 \(e.name)…", ok: true)
                    self.rebuild(e)
                }
            }
            watcher = w
        }
        watcher?.update(roots: roots)
        watching = roots.keys.sorted()
        watcher?.start()
        AKLogInfo("dev", "热重载已开启，盯着 \(roots.count) 个源码目录")
    }

    var devWatchActive: Bool { watcher?.isRunning ?? false }

    /// 重建成功后记一笔，界面显示「上次构建」
    func noteBuild(_ entry: ToolEntry, ok: Bool, text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        lastBuild[entry.id] = "\(ok ? "✓" : "✗") \(f.string(from: Date())) \(text)"
    }

    // MARK: 体检

    func runHealth(_ entry: ToolEntry) {
        guard let app = entry.installed else { return }
        Task {
            let report = await Task.detached { Health.check(app) }.value
            health[entry.id] = report
            let size = await Task.detached { Scanner.directorySize(app.path) }.value
            sizes[entry.id] = size
        }
    }

    func runHealthAll() {
        for e in entries where e.isInstalled { runHealth(e) }
        showToast("正在体检 \(installedCount) 个工具…", ok: true)
    }

    // MARK: 打开

    func open(_ entry: ToolEntry) {
        guard let app = entry.installed else {
            if entry.spec != nil {
                install(entry, isUpdate: false)
            } else {
                // 只在运行时注册过、LaunchServices 也定位不到 .app：没法打开
                showToast("找不到 \(entry.name) 的 .app 位置", ok: false)
            }
            return
        }
        NSWorkspace.shared.openApplication(at: app.path, configuration: NSWorkspace.OpenConfiguration()) { _, err in
            if let err { AKLogInfo("open", "\(err.localizedDescription)") }
        }
        usage.markOpened(entry.id)
        usage.save()
    }

    func reveal(_ entry: ToolEntry) {
        guard let app = entry.installed else { return }
        NSWorkspace.shared.activateFileViewerSelecting([app.path])
    }

    // MARK: 菜单栏下发

    func invoke(toolId: String, itemId: String) {
        server.invoke(toolId: toolId, itemId: itemId)
        AKLogInfo("hub", "invoke \(toolId) → \(itemId)")
    }

    /// 事件总线：广播给订阅了该事件的工具
    func emit(_ name: String, payload: [String: String] = [:], to toolId: String? = nil) {
        server.emit(name, payload: payload, to: toolId)
    }

    func toolInfo(_ bundleId: String) -> AKToolInfo? { connected[bundleId] }

    // MARK: 菜单栏布局
    func toggleHidden(_ entry: ToolEntry) {
        layout.setHidden(entry.id, !layout.isHidden(entry.id))
        layout.save()
        objectWillChange.send()
    }

    func move(_ entry: ToolEntry, to groupId: String) {
        layout.assign(entry.id, to: groupId)
        layout.save()
        objectWillChange.send()
    }

    func addGroup(_ title: String) {
        layout.groups.append(AKLayout.Group(id: UUID().uuidString.prefix(6).lowercased(), title: title))
        layout.save()
        objectWillChange.send()
    }

    func removeGroup(_ id: String) {
        guard layout.groups.count > 1 else { return }
        layout.groups.removeAll { $0.id == id }
        layout.save()
        objectWillChange.send()
    }

    // MARK: 设置

    func updateSettings(_ mutate: (inout AKSettings) -> Void) {
        let before = settings.devAutoRebuild
        mutate(&settings)
        settings.save()
        objectWillChange.send()
        if before != settings.devAutoRebuild {
            startDevWatchIfNeeded()
            showToast(settings.devAutoRebuild ? "热重载已开启" : "热重载已关闭", ok: true)
        }
    }

    // MARK: 导入导出

    func exportConfig() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "a-kit-config-\(Self.dateStamp()).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = ConfigBundle(version: 1, exportedAt: Date(),
                                  settings: settings, layout: layout, tools: entries.map { $0.id })
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try enc.encode(bundle).write(to: url)
            showToast("已导出到 \(url.lastPathComponent)", ok: true)
        } catch {
            showToast("导出失败：\(error.localizedDescription)", ok: false)
        }
    }

    func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let bundle = try JSONDecoder().decode(ConfigBundle.self, from: data)
            settings = bundle.settings
            settings.save()
            layout = bundle.layout
            layout.save()
            showToast("配置已导入", ok: true)
            Task { await rescan() }
        } catch {
            showToast("导入失败：\(error.localizedDescription)", ok: false)
        }
    }

    struct ConfigBundle: Codable {
        var version: Int
        var exportedAt: Date
        var settings: AKSettings
        var layout: AKLayout
        var tools: [String]
    }

    static func dateStamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    // MARK: 提示

    func showToast(_ text: String, ok: Bool) {
        let t = Toast(text: text, ok: ok)
        toast = t
        Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if toast?.id == t.id { toast = nil }
        }
    }

    // MARK: 菜单栏菜单（原生模式 / 右键）

    func menuItems(for tool: AKToolInfo, action: Selector, target: AnyObject) -> [NSMenuItem] {
        func build(_ items: [AKMenuItem]) -> [NSMenuItem] {
            items.map { item in
                switch item.kind {
                case .separator:
                    return .separator()
                case .header:
                    let mi = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                    mi.isEnabled = false
                    return mi
                case .item, .toggle:
                    let mi = NSMenuItem(title: item.title, action: action, keyEquivalent: "")
                    mi.target = target
                    mi.representedObject = [tool.bundleId, item.id]
                    mi.isEnabled = item.enabled
                    if item.kind == .toggle {
                        mi.state = (item.checked ?? false) ? .on : .off
                    }
                    if let sub = item.children, !sub.isEmpty {
                        let m = NSMenu()
                        build(sub).forEach { m.addItem($0) }
                        mi.submenu = m
                    }
                    return mi
                }
            }
        }
        return build(tool.menu)
    }

    // MARK: 插件落点

    func setPluginSlot(_ plugin: LoadedPlugin, _ slot: AKLayout.Slot) {
        layout.setSlot(slot, for: plugin.record.id)
        layout.save()
        objectWillChange.send()
        onLayoutChanged?()
    }

    func setPluginDisplay(_ plugin: LoadedPlugin, _ display: AKLayout.Display) {
        layout.setDisplay(display, for: plugin.record.id)
        layout.save()
        objectWillChange.send()
    }

    func setPanelStyle(_ style: AKLayout.PanelStyle) {
        layout.panelStyle = style.rawValue
        layout.save()
        objectWillChange.send()
    }
}
