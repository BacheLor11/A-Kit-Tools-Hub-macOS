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
            githubToken: ""
        )
    }

    public init(manifestURL: String, installDirectory: String, bundlePrefixes: [String],
                scanDirectories: [String], hotkey: String, launchAtLogin: Bool,
                autoCheckUpdates: Bool, keepBackups: Int, channel: String,
                showMenuBarIcon: Bool, showDockIcon: Bool, blogBaseURL: String,
                thirdPartyHiding: Bool, devAutoRebuild: Bool, githubToken: String = "") {
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
    }

    enum CodingKeys: String, CodingKey {
        case manifestURL, installDirectory, bundlePrefixes, scanDirectories, hotkey
        case launchAtLogin, autoCheckUpdates, keepBackups, channel, showMenuBarIcon
        case showDockIcon, blogBaseURL, thirdPartyHiding, devAutoRebuild, githubToken
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

    public static var `default`: AKLayout {
        AKLayout(groups: [Group(id: "main", title: "工具", collapsed: false)], hidden: [], clickBehavior: "panel")
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
