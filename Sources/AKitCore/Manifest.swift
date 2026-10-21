import Foundation

// MARK: - manifest.json 结构

/// 远端（或内置）工具清单。schemaVersion 目前为 1。
public struct Manifest: Codable {
    public var schemaVersion: Int
    public var generatedAt: String?
    public var tools: [ToolSpec]

    public init(schemaVersion: Int = 1, generatedAt: String? = nil, tools: [ToolSpec] = []) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.tools = tools
    }

    public func tool(id: String) -> ToolSpec? { tools.first { $0.id == id } }
}

public struct ToolSpec: Codable, Identifiable {
    public var id: String
    public var name: String
    public var tagline: String?
    public var bundleId: String
    public var category: String?          // tool / game / utility
    public var repo: String?              // GitHub owner/repo
    public var icon: String?              // 相对 manifest 的图标路径或绝对 URL
    public var article: String?           // 博客文章地址
    public var statusBar: StatusBarSpec?
    public var channels: [String: ChannelSpec]
    public var source: LocalSource?       // 本地源码（Dev 模式）

    public init(id: String, name: String, tagline: String? = nil, bundleId: String,
                category: String? = nil, repo: String? = nil, icon: String? = nil,
                article: String? = nil, statusBar: StatusBarSpec? = nil,
                channels: [String: ChannelSpec] = [:], source: LocalSource? = nil) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.bundleId = bundleId
        self.category = category
        self.repo = repo
        self.icon = icon
        self.article = article
        self.statusBar = statusBar
        self.channels = channels
        self.source = source
    }

    public func channel(_ name: String = "stable") -> ChannelSpec? {
        channels[name] ?? channels["stable"] ?? channels.values.first
    }
}

public struct StatusBarSpec: Codable {
    public var supported: Bool
    public var defaultVisible: Bool?

    public init(supported: Bool, defaultVisible: Bool? = nil) {
        self.supported = supported
        self.defaultVisible = defaultVisible
    }
}

public struct ChannelSpec: Codable {
    public var version: String
    public var build: Int?
    public var minOS: String?
    public var url: String?
    public var sha256: String?
    public var size: Int64?
    public var releasedAt: String?
    public var notes: String?

    public init(version: String, build: Int? = nil, minOS: String? = nil, url: String? = nil,
                sha256: String? = nil, size: Int64? = nil, releasedAt: String? = nil, notes: String? = nil) {
        self.version = version
        self.build = build
        self.minOS = minOS
        self.url = url
        self.sha256 = sha256
        self.size = size
        self.releasedAt = releasedAt
        self.notes = notes
    }

    public var akVersion: AKVersion { AKVersion(version, build: build ?? 0) }
}

public struct LocalSource: Codable {
    public var type: String              // swiftpm | xcode
    public var path: String
    public var build: String?            // 自定义构建命令
    public var appPath: String?          // 构建产物相对路径（可选）

    public init(type: String = "swiftpm", path: String, build: String? = nil, appPath: String? = nil) {
        self.type = type
        self.path = path
        self.build = build
        self.appPath = appPath
    }
}

// MARK: - 本机已安装的 app

public struct InstalledApp: Identifiable, Hashable {
    public var bundleId: String
    public var name: String
    public var version: String
    public var build: String
    public var path: URL
    public var sizeBytes: Int64
    public var modified: Date?

    public var id: String { bundleId }
    public var akVersion: AKVersion { AKVersion(version, build: Int(build) ?? 0) }
    public var displayVersion: String { build.isEmpty ? version : "\(version) (\(build))" }

    public init(bundleId: String, name: String, version: String, build: String,
                path: URL, sizeBytes: Int64 = 0, modified: Date? = nil) {
        self.bundleId = bundleId
        self.name = name
        self.version = version
        self.build = build
        self.path = path
        self.sizeBytes = sizeBytes
        self.modified = modified
    }
}

// MARK: - 合并后的条目

public struct ToolEntry: Identifiable {
    public var id: String
    public var spec: ToolSpec?
    public var installed: InstalledApp?
    public var latest: ChannelSpec?
    public var channelName: String
    /// 只在运行时成立的名字：给「只通过 SDK 接入、还没登记」的工具兜底显示。
    /// 正规来源优先，它只排在 id 前面。
    public var runtimeName: String?

    public var name: String { spec?.name ?? installed?.name ?? runtimeName ?? id }
    public var tagline: String { spec?.tagline ?? "" }
    public var isInstalled: Bool { installed != nil }
    /// 不在清单里、也没被扫描登记，只靠 SDK 注册上来的
    public var isRuntimeOnly: Bool { spec == nil && installed == nil }

    public var updateAvailable: Bool {
        guard let installed, let latest else { return false }
        return latest.akVersion > installed.akVersion
    }

    public init(id: String, spec: ToolSpec?, installed: InstalledApp?, latest: ChannelSpec?,
                channelName: String = "stable", runtimeName: String? = nil) {
        self.id = id
        self.spec = spec
        self.installed = installed
        self.latest = latest
        self.channelName = channelName
        self.runtimeName = runtimeName
    }
}

public enum Registry {
    /// 清单 + 本机扫描结果合并。清单里没有但本机装了（且命中 bundle 前缀）的，也算进来。
    public static func merge(manifest: Manifest?, installed: [InstalledApp],
                             channel: String = "stable",
                             fallbackIds: [String] = []) -> [ToolEntry] {
        var entries: [ToolEntry] = []
        var usedBundleIds = Set<String>()

        for spec in manifest?.tools ?? [] {
            let app = installed.first { $0.bundleId == spec.bundleId }
                ?? installed.first { $0.name.lowercased() == spec.name.lowercased() }
            if let app { usedBundleIds.insert(app.bundleId) }
            entries.append(ToolEntry(id: spec.id, spec: spec, installed: app,
                                     latest: spec.channel(channel), channelName: channel))
        }

        // 清单里没登记、但本机存在的自家 app
        for app in installed where !usedBundleIds.contains(app.bundleId) {
            if !fallbackIds.isEmpty && !fallbackIds.contains(app.bundleId) { continue }
            entries.append(ToolEntry(id: app.bundleId, spec: nil, installed: app, latest: nil))
        }

        return entries.sorted { a, b in
            if a.isInstalled != b.isInstalled { return a.isInstalled }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
