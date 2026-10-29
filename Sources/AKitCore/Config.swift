import Foundation

// MARK: - 设置

public struct AKSettings: Codable {
    public var manifestURL: String
    public var installDirectory: String
    public var bundlePrefixes: [String]
    public var scanDirectories: [String]
    public var hotkey: String
    public var launchAtLogin: Bool
    public var autoCheckUpdates: Bool
    public var keepBackups: Int
    public var channel: String
    public var showMenuBarIcon: Bool
    public var showDockIcon: Bool
    public var blogBaseURL: String
    public var thirdPartyHiding: Bool
    public var devAutoRebuild: Bool
    /// 可选：GitHub Personal Access Token（只读 public_repo 就够），用于放宽 API 限流
    public var githubToken: String
    /// 工具通过 SDK 连上来时，自动写进本机清单 —— 否则它一退出就从列表里消失
    public var autoRegisterTools: Bool
    /// 菜单栏图标画多大（pt）。系统标准是 18，觉得小可以调到 20/22。
    public var menuBarIconSize: Double

    public static var `default`: AKSettings {
        AKSettings(
            manifestURL: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS/releases/latest/download/manifest.json",
            installDirectory: "~/Applications",
            bundlePrefixes: [],
            scanDirectories: ["/Applications", "~/Applications"],
            hotkey: "cmd+shift+a",
            launchAtLogin: false,
            autoCheckUpdates: true,
            keepBackups: 3,
            channel: "stable",
            showMenuBarIcon: true,
            showDockIcon: true,
            blogBaseURL: "https://askb.app",
            thirdPartyHiding: false,
            devAutoRebuild: false,
            githubToken: "",
            autoRegisterTools: true,
            menuBarIconSize: 18
        )
    }

    public init(manifestURL: String, installDirectory: String, bundlePrefixes: [String],
                scanDirectories: [String], hotkey: String, launchAtLogin: Bool,
                autoCheckUpdates: Bool, keepBackups: Int, channel: String,
                showMenuBarIcon: Bool, showDockIcon: Bool, blogBaseURL: String,
                thirdPartyHiding: Bool, devAutoRebuild: Bool, githubToken: String = "",
                autoRegisterTools: Bool = true, menuBarIconSize: Double = 18) {
        self.manifestURL = manifestURL
        self.installDirectory = installDirectory
        self.bundlePrefixes = bundlePrefixes
        self.scanDirectories = scanDirectories
        self.hotkey = hotkey
        self.launchAtLogin = launchAtLogin
        self.autoCheckUpdates = autoCheckUpdates
        self.keepBackups = keepBackups
        self.channel = channel
        self.showMenuBarIcon = showMenuBarIcon
        self.showDockIcon = showDockIcon
        self.blogBaseURL = blogBaseURL
        self.thirdPartyHiding = thirdPartyHiding
        self.devAutoRebuild = devAutoRebuild
        self.githubToken = githubToken
        self.autoRegisterTools = autoRegisterTools
        self.menuBarIconSize = menuBarIconSize
    }

    enum CodingKeys: String, CodingKey {
        case manifestURL, installDirectory, bundlePrefixes, scanDirectories, hotkey
        case launchAtLogin, autoCheckUpdates, keepBackups, channel, showMenuBarIcon
        case showDockIcon, blogBaseURL, thirdPartyHiding, devAutoRebuild, githubToken
        case autoRegisterTools, menuBarIconSize
    }

    /// 宽容解码：旧版配置文件里没有的新字段一律回落到默认值，不会因为加字段就把设置全清空
    public init(from decoder: Decoder) throws {
        let d = AKSettings.default
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func str(_ k: CodingKeys, _ fallback: String) -> String {
            (try? c.decodeIfPresent(String.self, forKey: k)) ?? fallback
        }
        func bool(_ k: CodingKeys, _ fallback: Bool) -> Bool {
            (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? fallback
        }
        manifestURL = str(.manifestURL, d.manifestURL)
        installDirectory = str(.installDirectory, d.installDirectory)
        bundlePrefixes = (try? c.decodeIfPresent([String].self, forKey: .bundlePrefixes)) ?? d.bundlePrefixes
        scanDirectories = (try? c.decodeIfPresent([String].self, forKey: .scanDirectories)) ?? d.scanDirectories
        hotkey = str(.hotkey, d.hotkey)
        launchAtLogin = bool(.launchAtLogin, d.launchAtLogin)
        autoCheckUpdates = bool(.autoCheckUpdates, d.autoCheckUpdates)
        keepBackups = (try? c.decodeIfPresent(Int.self, forKey: .keepBackups)) ?? d.keepBackups
        channel = str(.channel, d.channel)
        showMenuBarIcon = bool(.showMenuBarIcon, d.showMenuBarIcon)
        showDockIcon = bool(.showDockIcon, d.showDockIcon)
        blogBaseURL = str(.blogBaseURL, d.blogBaseURL)
        thirdPartyHiding = bool(.thirdPartyHiding, d.thirdPartyHiding)
        devAutoRebuild = bool(.devAutoRebuild, d.devAutoRebuild)
        githubToken = str(.githubToken, "")
        autoRegisterTools = bool(.autoRegisterTools, d.autoRegisterTools)
        menuBarIconSize = (try? c.decodeIfPresent(Double.self, forKey: .menuBarIconSize)) ?? d.menuBarIconSize
    }

    public static func load() -> AKSettings {
        guard let data = try? Data(contentsOf: AKPaths.settingsFile),
              let s = try? JSONDecoder().decode(AKSettings.self, from: data) else {
            return .default
        }
        return s
    }

    public func save() {
        AKPaths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: AKPaths.settingsFile)
        }
    }
}

// MARK: - 菜单栏布局

public struct AKLayout: Codable {
    public struct Group: Codable, Identifiable {
        public var id: String
        public var title: String
        public var items: [String]
        public var collapsed: Bool

        public init(id: String, title: String, items: [String] = [], collapsed: Bool = false) {
            self.id = id
            self.title = title
            self.items = items
            self.collapsed = collapsed
        }
    }

    public var groups: [Group]
    public var hidden: [String]
    public var clickBehavior: String      // panel / menu

    // MARK: 插件落点与排布
    //
    // 三个维度互相独立：
    // - slot：这个插件在**系统菜单栏**里怎么出现（bar / hubbar / board / hidden）
    // - display：这个插件在**面板里**怎么出现（expanded / collapsed / hidden）
    // - panelStyle：面板整体形态（cards / accordion / compact）
    //
    // 用 optional 是为了兼容老 layout.json，缺字段时走默认值。

    /// pluginId → bar（自己持有图标）/ hubbar（Hub 代持）/ board（只进面板）/ hidden
    public var slot: [String: String]?
    /// pluginId → expanded / collapsed / hidden
    public var display: [String: String]?
    /// 面板整体形态
    public var panelStyle: String?

    public static var `default`: AKLayout {
        AKLayout(groups: [Group(id: "main", title: "工具", collapsed: false)],
                 hidden: [], clickBehavior: "panel",
                 slot: nil, display: nil, panelStyle: "cards")
    }

    public enum Slot: String, CaseIterable {
        case bar, hubbar, board, hidden

        public var title: String {
            switch self {
            case .bar: return "菜单栏 · 自己持有"
            case .hubbar: return "菜单栏 · A-Kit 代持"
            case .board: return "只进 A-Kit 面板"
            case .hidden: return "不显示"
            }
        }

        public var symbol: String {
            switch self {
            case .bar: return "menubar.rectangle"
            case .hubbar: return "square.grid.2x2"
            case .board: return "rectangle.on.rectangle"
            case .hidden: return "eye.slash"
            }
        }
    }

    public enum Display: String, CaseIterable {
        case expanded, collapsed, hidden

        public var title: String {
            switch self {
            case .expanded: return "默认展开"
            case .collapsed: return "折叠成一行"
            case .hidden: return "面板里不显示"
            }
        }
    }

    public enum PanelStyle: String, CaseIterable {
        case cards, accordion, compact

        public var title: String {
            switch self {
            case .cards: return "卡片流"
            case .accordion: return "手风琴（只开一个）"
            case .compact: return "紧凑列表"
            }
        }

        public var hint: String {
            switch self {
            case .cards: return "每个工具各自展开、各自折叠，适合工具少"
            case .accordion: return "同一时刻只展开一个，适合工具多"
            case .compact: return "全部收成一行，点了才展开，最省空间"
            }
        }
    }

    /// 默认落点是 `board`（只进 A-Kit 面板），**不是** `hubbar`。
    ///
    /// 以前默认 hubbar，装一个插件就在系统菜单栏多一格图标 ——
    /// 用户装完看到菜单栏凭空多出几个方块，第一反应是「这什么鬼」。
    /// 想让它上菜单栏，用户自己在「菜单栏」页显式开启。
    public func slot(for pluginId: String) -> Slot {
        Slot(rawValue: slot?[pluginId] ?? "") ?? .board
    }

    public mutating func setSlot(_ value: Slot, for pluginId: String) {
        var m = slot ?? [:]
        m[pluginId] = value.rawValue
        slot = m
    }

    public func display(for pluginId: String) -> Display {
        Display(rawValue: display?[pluginId] ?? "") ?? .collapsed
    }

    public mutating func setDisplay(_ value: Display, for pluginId: String) {
        var m = display ?? [:]
        m[pluginId] = value.rawValue
        display = m
    }

    public var resolvedPanelStyle: PanelStyle {
        PanelStyle(rawValue: panelStyle ?? "") ?? .cards
    }

    public static func load() -> AKLayout {
        guard let data = try? Data(contentsOf: AKPaths.layoutFile),
              let l = try? JSONDecoder().decode(AKLayout.self, from: data) else {
            return .default
        }
        return l
    }

    public func save() {
        AKPaths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: AKPaths.layoutFile)
        }
    }

    public func isHidden(_ toolId: String) -> Bool { hidden.contains(toolId) }

    public mutating func setHidden(_ toolId: String, _ value: Bool) {
        if value {
            if !hidden.contains(toolId) { hidden.append(toolId) }
        } else {
            hidden.removeAll { $0 == toolId }
        }
    }

    /// 把工具放进分组，顺手从其它分组里移除
    public mutating func assign(_ toolId: String, to groupId: String) {
        for i in groups.indices {
            groups[i].items.removeAll { $0 == toolId }
        }
        if let idx = groups.firstIndex(where: { $0.id == groupId }) {
            groups[idx].items.append(toolId)
        }
    }

    /// 按 layout 顺序摊平出要显示的工具 id
    public var visibleOrder: [String] {
        groups.flatMap { $0.items }.filter { !hidden.contains($0) }
    }

    /// 彻底忘掉一个 id：分组、隐藏、落点、面板形态全都清掉。
    /// 用于「把插件移出 A-Kit」—— 否则 layout.json 里会留下指向已删插件的死条目。
    public mutating func forget(_ id: String) {
        hidden.removeAll { $0 == id }
        for i in groups.indices {
            groups[i].items.removeAll { $0 == id }
        }
        slot?.removeValue(forKey: id)
        display?.removeValue(forKey: id)
    }
}

// MARK: - 使用统计

public struct AKUsage: Codable {
    public struct Record: Codable {
        public var lastOpened: Date?
        public var openCount: Int
    }
    public var records: [String: Record] = [:]

    public static func load() -> AKUsage {
        guard let data = try? Data(contentsOf: AKPaths.usageFile),
              let u = try? JSONDecoder().decode(AKUsage.self, from: data) else { return AKUsage() }
        return u
    }

    public func save() {
        AKPaths.ensure()
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: AKPaths.usageFile) }
    }

    public mutating func markOpened(_ toolId: String) {
        var r = records[toolId] ?? Record(lastOpened: nil, openCount: 0)
        r.lastOpened = Date()
        r.openCount += 1
        records[toolId] = r
    }

    public func daysSinceOpened(_ toolId: String) -> Int? {
        guard let d = records[toolId]?.lastOpened else { return nil }
        return Calendar.current.dateComponents([.day], from: d, to: Date()).day
    }
}
