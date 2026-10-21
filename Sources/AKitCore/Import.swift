import Foundation

// MARK: - 工具自描述：akit.json
//
// 约定放在仓库根目录（也接受 .akit/tool.json）。有了它，A-Kit 能：
//   · 知道这个工具叫什么、bundle id 是什么、支不支持菜单栏
//   · 从 Release 的多个产物里挑对那一个（asset 通配）
//   · 装完做 bundle id 校验，防止下错包
// 没有它也能装 —— 只是要靠文件名猜，装完才校验。

public struct AKToolManifest: Codable {
    public var schemaVersion: Int?
    public var id: String?
    public var name: String?
    public var tagline: String?
    public var bundleId: String?
    public var category: String?
    public var minOS: String?
    public var article: String?
    public var icon: String?
    /// 挑选产物的通配（如 "NetPulse-*.zip"）或子串
    public var asset: String?
    public var sha256: String?
    public var statusBar: StatusBarSpec?

    public init(schemaVersion: Int? = 1, id: String? = nil, name: String? = nil,
                tagline: String? = nil, bundleId: String? = nil, category: String? = nil,
                minOS: String? = nil, article: String? = nil, icon: String? = nil,
                asset: String? = nil, sha256: String? = nil, statusBar: StatusBarSpec? = nil) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.tagline = tagline
        self.bundleId = bundleId
        self.category = category
        self.minOS = minOS
        self.article = article
        self.icon = icon
        self.asset = asset
        self.sha256 = sha256
        self.statusBar = statusBar
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, tagline, bundleId, category
        case minOS, article, icon, asset, sha256, statusBar, menuBar
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        tagline = try? c.decodeIfPresent(String.self, forKey: .tagline)
        bundleId = try? c.decodeIfPresent(String.self, forKey: .bundleId)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        minOS = try? c.decodeIfPresent(String.self, forKey: .minOS)
        article = try? c.decodeIfPresent(String.self, forKey: .article)
        icon = try? c.decodeIfPresent(String.self, forKey: .icon)
        asset = try? c.decodeIfPresent(String.self, forKey: .asset)
        sha256 = try? c.decodeIfPresent(String.self, forKey: .sha256)

        // statusBar 允许两种写法：true / { "supported": true }
        if let spec = try? c.decodeIfPresent(StatusBarSpec.self, forKey: .statusBar) {
            statusBar = spec
        } else if let flag = try? c.decodeIfPresent(Bool.self, forKey: .statusBar) {
            statusBar = StatusBarSpec(supported: flag)
        } else if let flag = try? c.decodeIfPresent(Bool.self, forKey: .menuBar) {
            statusBar = StatusBarSpec(supported: flag)
        } else {
            statusBar = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(schemaVersion, forKey: .schemaVersion)
        try c.encodeIfPresent(id, forKey: .id)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(tagline, forKey: .tagline)
        try c.encodeIfPresent(bundleId, forKey: .bundleId)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(minOS, forKey: .minOS)
        try c.encodeIfPresent(article, forKey: .article)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(asset, forKey: .asset)
        try c.encodeIfPresent(sha256, forKey: .sha256)
        try c.encodeIfPresent(statusBar, forKey: .statusBar)
    }
}

// MARK: - 从 GitHub 装进来的工具（本地记录）

public struct ImportedTool: Codable, Identifiable {
    public var id: String
    public var name: String
    public var bundleId: String
    public var owner: String?
    public var repo: String?
    public var tag: String
    public var version: String
    public var assetName: String
    public var assetURL: String
    public var tagline: String?
    public var article: String?
    public var iconURL: String?
    public var supportsStatusBar: Bool
    public var addedAt: String
    public var installedPath: String?
    public var sourceInput: String?

    public init(id: String, name: String, bundleId: String, owner: String? = nil, repo: String? = nil,
                tag: String, version: String, assetName: String, assetURL: String,
                tagline: String? = nil, article: String? = nil, iconURL: String? = nil,
                supportsStatusBar: Bool = true, addedAt: String = ISO8601DateFormatter().string(from: Date()),
                installedPath: String? = nil, sourceInput: String? = nil) {
        self.id = id
        self.name = name
        self.bundleId = bundleId
        self.owner = owner
        self.repo = repo
        self.tag = tag
        self.version = version
        self.assetName = assetName
        self.assetURL = assetURL
        self.tagline = tagline
        self.article = article
        self.iconURL = iconURL
        self.supportsStatusBar = supportsStatusBar
        self.addedAt = addedAt
        self.installedPath = installedPath
        self.sourceInput = sourceInput
    }

    public var slug: String? {
        guard let owner, let repo else { return nil }
        return "\(owner)/\(repo)"
    }

    /// 变成一个正常的工具条目，跟内置清单里的工具走同一套逻辑
    public func spec() -> ToolSpec {
        ToolSpec(id: id, name: name, tagline: tagline, bundleId: bundleId,
                 category: "tool", repo: slug, icon: iconURL, article: article,
                 statusBar: StatusBarSpec(supported: supportsStatusBar),
                 channels: ["stable": ChannelSpec(version: version, url: assetURL, notes: tag)])
    }
}

public enum ImportedStore {
    public static func load() -> [ImportedTool] {
        guard let data = try? Data(contentsOf: AKPaths.importedFile),
              let list = try? JSONDecoder().decode([ImportedTool].self, from: data) else { return [] }
        return list
    }

    public static func save(_ list: [ImportedTool]) {
        AKPaths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(list) { try? data.write(to: AKPaths.importedFile) }
    }

    public static func upsert(_ tool: ImportedTool) {
        var list = load()
        if let i = list.firstIndex(where: { $0.id == tool.id }) { list[i] = tool }
        else { list.append(tool) }
        save(list)
    }

    public static func remove(id: String) {
        save(load().filter { $0.id != id })
    }

    public static func all() -> [ImportedTool] { load() }
}

// MARK: - 安装

public enum ImportInstallError: LocalizedError {
    case pkgNotSupported
    case noAppInImage
    case mountFailed(String)
    case noBundleId
    case bundleMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .pkgNotSupported: return "PKG 安装包需要管理员密码，A-Kit 不代跑 sudo。请手动安装后重新扫描"
        case .noAppInImage: return "磁盘映像/压缩包里没有 .app"
        case .mountFailed(let s): return "挂载 DMG 失败：\(s)"
        case .noBundleId: return "这个包没有 CFBundleIdentifier，不像是能安装的 app"
        case .bundleMismatch(let e, let a): return "下载的包和清单对不上（清单 \(e)，包里 \(a)），已中止"
        }
    }
}

public enum ImportInstaller {

    @discardableResult
    public static func install(_ c: ImportCandidate, into dir: URL, backupRoot: URL,
                               progress: @escaping (String) -> Void) async throws -> ImportedTool {
        guard !c.needsSudo else { throw ImportInstallError.pkgNotSupported }
        AKPaths.ensure()

        progress("下载 \(c.assetName)…")
        guard let url = URL(string: c.assetURL) else { throw InstallerError.downloadFailed("链接无效") }
        let local = AKPaths.downloads.appendingPathComponent(c.assetName)
        let file = try await Installer.download(from: url, to: local)

        if let expected = c.sha256, !expected.isEmpty {
            progress("校验 SHA-256…")
            let actual = try Installer.sha256(at: file)
            guard actual.lowercased() == expected.lowercased() else {
                throw InstallerError.checksumMismatch(expected: expected, actual: actual)
            }
        }

        progress("解包…")
        let stage = AKPaths.downloads.appendingPathComponent("import-\(UUID().uuidString.prefix(8))")
        let app: URL
        if c.assetName.lowercased().hasSuffix(".dmg") {
            app = try extractDMG(file, into: stage)
        } else if c.assetName.lowercased().hasSuffix(".pkg") {
            throw ImportInstallError.pkgNotSupported
        } else {
            app = try Installer.unzip(file, into: stage)
        }

        // 读包里真实的身份
        let bundle = Bundle(url: app)
        let actualId = bundle?.bundleIdentifier ?? ""
        guard !actualId.isEmpty else { throw ImportInstallError.noBundleId }
        if !c.bundleId.isEmpty, c.bundleId != actualId {
            throw ImportInstallError.bundleMismatch(expected: c.bundleId, actual: actualId)
        }
        let realName = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? c.name
        let realVersion = (bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? c.version

        progress("安装到 \(dir.lastPathComponent)…")
        let existing = Scanner.readApp(at: dir.appendingPathComponent(app.lastPathComponent))
        var installed: URL
        if let existing, Scanner.isRunning(bundleId: actualId) {
            let staged = try Installer.install(app, into: stage.appendingPathComponent("final"),
                                               expectedBundleId: actualId)
            try Installer.replaceWhileRunning(newApp: staged, target: existing.path, relaunch: false)
            installed = existing.path
        } else {
            installed = try Installer.install(app, into: dir,
                                              backupTo: backupRoot.appendingPathComponent(realName),
                                              expectedBundleId: actualId)
        }

        try? FileManager.default.removeItem(at: stage)
        try? FileManager.default.removeItem(at: file)

        let id = c.owner != nil ? "gh-\(c.owner!)-\(c.repo!)".lowercased()
                              : "direct-\(actualId)".lowercased()
        // 有 akit.json 就用它写的名字（作者自己定的更准），否则用包里读到的
        let displayName = (c.hasAKitManifest && !c.name.isEmpty) ? c.name : realName
        let record = ImportedTool(
            id: c.id.hasPrefix("gh-") || c.isDirect ? id : c.id,
            name: displayName,
            bundleId: actualId,
            owner: c.owner, repo: c.repo,
            tag: c.tag,
            version: c.version.isEmpty ? realVersion : c.version,
            assetName: c.assetName,
            assetURL: c.assetURL,
            tagline: c.tagline.isEmpty ? nil : c.tagline,
            article: c.article,
            iconURL: c.iconURL,
            supportsStatusBar: c.supportsStatusBar,
            installedPath: installed.path,
            sourceInput: c.input
        )
        ImportedStore.upsert(record)
        progress("完成：\(realName) \(realVersion)")
        AKLogInfo("import", "installed \(actualId) \(realVersion) from \(c.input)")
        return record
    }

    /// 挂载 dmg → 把里面的 .app 拷到临时目录 → 卸载
    public static func extractDMG(_ dmg: URL, into stage: URL) throws -> URL {
        let mount = FileManager.default.temporaryDirectory
            .appendingPathComponent("akit-mnt-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        let (code, out) = Shell.run("/usr/bin/hdiutil", [
            "attach", "-nobrowse", "-readonly", "-noverify", "-noautoopen",
            "-mountpoint", mount.path, dmg.path,
        ])
        guard code == 0 else {
            try? FileManager.default.removeItem(at: mount)
            throw ImportInstallError.mountFailed(String(out.suffix(300)))
        }
        defer {
            Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? FileManager.default.removeItem(at: mount)
        }
        guard let inside = Installer.appInside(mount) else { throw ImportInstallError.noAppInImage }
        try? FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let dest = stage.appendingPathComponent(inside.lastPathComponent)
        let (c2, o2) = Shell.run("/usr/bin/ditto", [inside.path, dest.path])
        guard c2 == 0 else { throw InstallerError.installFailed(o2) }
        return dest
    }
}
