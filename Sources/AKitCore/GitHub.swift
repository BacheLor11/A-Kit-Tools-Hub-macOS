import Foundation

// MARK: - 输入解析

/// 从「一行网址」里解析出来的 GitHub 坐标
public struct GitHubRepo: Hashable {
    public var owner: String
    public var repo: String
    public var tag: String?      // nil = 最新 release

    public init(owner: String, repo: String, tag: String? = nil) {
        self.owner = owner
        self.repo = repo
        self.tag = tag
    }

    public var slug: String { "\(owner)/\(repo)" }
    public var webURL: String { "https://github.com/\(owner)/\(repo)" }
}

public struct ImportRequest {
    public enum Source {
        case repo(GitHubRepo)
        /// Release 里的某个具体产物：仍然知道 repo/tag，所以还能检查更新
        case releaseAsset(GitHubRepo, String)
        case direct(URL)          // 任意 http(s) 直链：.zip / .dmg / .pkg
    }
    public var source: Source
    public var raw: String
}

public enum ImportParseError: LocalizedError {
    case empty
    case notSupported(String)
    case badRepo

    public var errorDescription: String? {
        switch self {
        case .empty: return "请输入一个 GitHub 仓库或下载链接"
        case .notSupported(let s): return "看不懂这个链接：\(s)"
        case .badRepo: return "地址里没有 owner/repo"
        }
    }
}

public enum GitHubURLParser {

    /// 支持这几种写法：
    /// - `https://github.com/owner/repo`
    /// - `https://github.com/owner/repo/releases/tag/v1.2.0`
    /// - `https://github.com/owner/repo/releases/download/v1.2.0/X.zip`
    /// - `owner/repo`（简写）
    /// - 任意 `https://…/X.zip|X.dmg|X.pkg` 直链
    public static func parse(_ raw: String) throws -> ImportRequest {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { throw ImportParseError.empty }

        // git@github.com:owner/repo.git
        if s.hasPrefix("git@github.com:") {
            s = "https://github.com/" + s.replacingOccurrences(of: "git@github.com:", with: "")
        }
        if s.hasSuffix(".git") { s = String(s.dropLast(4)) }
        if !s.contains("://") {
            if s.contains("github.com/") { s = "https://" + s }
            else if s.hasSuffix(".zip") || s.hasSuffix(".dmg") || s.hasSuffix(".pkg") {
                throw ImportParseError.notSupported("直链要以 http(s):// 开头")
            } else {
                // owner/repo 简写
                let parts = s.split(separator: "/").map(String.init)
                guard parts.count >= 2 else { throw ImportParseError.badRepo }
                return ImportRequest(source: .repo(GitHubRepo(owner: parts[0], repo: parts[1])), raw: raw)
            }
        }

        guard let url = URL(string: s), let host = url.host?.lowercased() else {
            throw ImportParseError.notSupported(raw)
        }
        let parts = url.path.split(separator: "/").map(String.init)

        if host == "github.com" || host == "www.github.com" {
            guard parts.count >= 2 else { throw ImportParseError.badRepo }
            let owner = parts[0]
            let repo = parts[1]
            if parts.count >= 5, parts[2] == "releases" {
                if parts[3] == "tag" {
                    return ImportRequest(source: .repo(GitHubRepo(owner: owner, repo: repo, tag: parts[4])), raw: raw)
                }
                if parts[3] == "download" {
                    // Release 里的具体产物：保留 repo + tag，装完照样能检查更新
                    let tag = parts.count > 4 ? parts[4] : ""
                    let file = parts.count > 5 ? parts[5...].joined(separator: "/") : ""
                    if !tag.isEmpty {
                        return ImportRequest(
                            source: .releaseAsset(GitHubRepo(owner: owner, repo: repo, tag: tag), file),
                            raw: raw
                        )
                    }
                    return ImportRequest(source: .direct(url), raw: raw)
                }
            }
            if parts.count >= 4, parts[2] == "releases", parts[3] == "latest" {
                return ImportRequest(source: .repo(GitHubRepo(owner: owner, repo: repo)), raw: raw)
            }
            return ImportRequest(source: .repo(GitHubRepo(owner: owner, repo: repo)), raw: raw)
        }

        let ext = url.pathExtension.lowercased()
        if ["zip", "dmg", "pkg"].contains(ext) {
            return ImportRequest(source: .direct(url), raw: raw)
        }
        throw ImportParseError.notSupported("只支持 GitHub 仓库地址，或 .zip / .dmg / .pkg 直链")
    }
}

// MARK: - GitHub API

public struct GHAsset: Codable, Hashable {
    public var name: String
    public var url: String
    public var size: Int64?

    enum CodingKeys: String, CodingKey {
        case name
        case url = "browser_download_url"
        case size
    }

    public init(name: String, url: String, size: Int64? = nil) {
        self.name = name
        self.url = url
        self.size = size
    }
}

public struct GHRelease: Codable {
    public var tag: String
    public var name: String?
    public var body: String?
    public var publishedAt: String?
    public var prerelease: Bool?
    public var htmlURL: String?
    public var assets: [GHAsset]

    enum CodingKeys: String, CodingKey {
        case tag = "tag_name"
        case name, body, prerelease, assets
        case publishedAt = "published_at"
        case htmlURL = "html_url"
    }
}

public enum GitHubError: LocalizedError {
    case http(Int, String)
    case noRelease(String)
    case noAsset(String)
    case rateLimited

    public var errorDescription: String? {
        switch self {
        case .http(let code, let body):
            if code == 404 { return "仓库或 Release 不存在（404）" }
            if code == 403 { return "GitHub 限流了（403）。在设置里填一个 Token 可以放宽到 5000 次/小时" }
            return "GitHub 返回 HTTP \(code)：\(body.prefix(160))"
        case .noRelease(let slug): return "\(slug) 还没有发布过 Release"
        case .noAsset(let name): return "\(name) 的 Release 里没有可安装的 .zip / .dmg"
        case .rateLimited: return "GitHub API 限流，请稍后再试或配置 Token"
        }
    }
}

public enum GitHubAPI {

    /// 可覆盖，方便自建 GitHub（Enterprise）或本地测试
    static var apiBase: String {
        ProcessInfo.processInfo.environment["AKIT_GITHUB_API"] ?? "https://api.github.com"
    }
    static var rawBase: String {
        ProcessInfo.processInfo.environment["AKIT_GITHUB_RAW"] ?? "https://raw.githubusercontent.com"
    }

    static func request(_ url: URL, token: String?) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("A-Kit/1.0", forHTTPHeaderField: "User-Agent")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw GitHubError.http(-1, "no response")
        }
        if http.statusCode == 403, http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
            throw GitHubError.rateLimited
        }
        if http.statusCode >= 400 {
            throw GitHubError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return (data, http)
    }

    public static func latestRelease(owner: String, repo: String, tag: String? = nil,
                                     token: String? = nil) async throws -> GHRelease {
        let path = tag == nil
            ? "\(apiBase)/repos/\(owner)/\(repo)/releases/latest"
            : "\(apiBase)/repos/\(owner)/\(repo)/releases/tags/\(tag!)"
        do {
            let (data, _) = try await request(URL(string: path)!, token: token)
            return try JSONDecoder().decode(GHRelease.self, from: data)
        } catch let e as GitHubError {
            // latest 在「只有预发布」的仓库会 404，退回列表第一个
            if case .http(404, _) = e, tag == nil {
                let (data, _) = try await request(
                    URL(string: "\(apiBase)/repos/\(owner)/\(repo)/releases?per_page=5")!,
                    token: token)
                let list = try JSONDecoder().decode([GHRelease].self, from: data)
                guard let first = list.first else { throw GitHubError.noRelease("\(owner)/\(repo)") }
                return first
            }
            throw e
        }
    }

    /// 仓库的默认分支。raw 地址**不认 `HEAD`**（会 404），必须用真实分支名。
    static func defaultBranch(owner: String, repo: String, token: String?) async -> String? {
        guard let url = URL(string: "\(apiBase)/repos/\(owner)/\(repo)") else { return nil }
        guard let (data, _) = try? await request(url, token: token) else { return nil }
        struct RepoInfo: Decodable { let default_branch: String? }
        return (try? JSONDecoder().decode(RepoInfo.self, from: data))?.default_branch
    }

    /// 读取仓库里的 `akit.json`（约定放在根目录，也可放 .akit/tool.json）。
    /// 先按 release 的 tag 取，取不到再退回默认分支。
    public static func toolManifest(owner: String, repo: String, tag: String?,
                                    token: String? = nil) async throws -> AKToolManifest? {
        var refs: [String] = []
        if let tag { refs.append(tag) }
        if let branch = await defaultBranch(owner: owner, repo: repo, token: token) {
            refs.append(branch)
        }
        // API 不通（限流 / Enterprise）时的兜底
        refs.append(contentsOf: ["main", "master"])

        var seen = Set<String>()
        let names = ["akit.json", ".akit/tool.json"]
        for ref in refs where seen.insert(ref).inserted {
            for name in names {
                guard let url = URL(string: "\(rawBase)/\(owner)/\(repo)/\(ref)/\(name)") else { continue }
                var req = URLRequest(url: url)
                req.timeoutInterval = 12
                req.setValue("A-Kit/1.0", forHTTPHeaderField: "User-Agent")
                guard let (data, resp) = try? await URLSession.shared.data(for: req),
                      let http = resp as? HTTPURLResponse, http.statusCode == 200 else { continue }
                if let m = try? JSONDecoder().decode(AKToolManifest.self, from: data) {
                    return m
                }
            }
        }
        return nil
    }

    /// 通用 GET（给直链测大小 / 读 akit.json 用）
    public static func head(_ url: URL, token: String? = nil) async throws -> (Int64?, String?) {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 15
        req.setValue("A-Kit/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return (nil, nil) }
        if http.statusCode >= 400 { throw GitHubError.http(http.statusCode, url.absoluteString) }
        let size = http.value(forHTTPHeaderField: "Content-Length").flatMap { Int64($0) }
        let name = http.value(forHTTPHeaderField: "Content-Disposition")?
            .components(separatedBy: "filename=").last?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        return (size, name)
    }
}

// MARK: - 候选

/// 解析出来、还没安装的候选。UI 拿它渲染预览卡片。
public struct ImportCandidate {
    public var id: String
    public var input: String
    public var owner: String?
    public var repo: String?
    public var name: String
    public var tagline: String
    public var bundleId: String
    public var version: String
    public var tag: String
    public var article: String?
    public var iconURL: String?
    public var notes: String?
    public var assetName: String
    public var assetURL: String
    public var assetSize: Int64?
    public var sha256: String?
    public var supportsStatusBar: Bool
    public var hasAKitManifest: Bool
    public var minOS: String?
    public var isDirect: Bool
    public var publishedAt: String?
    public var isPrerelease: Bool
    public var warnings: [String]

    public var slug: String? {
        guard let owner, let repo else { return nil }
        return "\(owner)/\(repo)"
    }
    public var installKind: String {
        let ext = (assetName as NSString).pathExtension.lowercased()
        switch ext {
        case "dmg": return "DMG 磁盘映像"
        case "pkg": return "PKG 安装包（需要管理员权限）"
        default: return "ZIP 压缩包"
        }
    }
    public var needsSudo: Bool { assetName.lowercased().hasSuffix(".pkg") }
}

// MARK: - 选包

public enum AssetPicker {
    static let badWords = ["source", "symbols", "dSYM", "sha256", "checksum", "manifest"]

    public static func pick(_ assets: [GHAsset], manifest: AKToolManifest?) -> GHAsset? {
        let usable = assets.filter { a in
            let n = a.name.lowercased()
            let ext = (n as NSString).pathExtension
            guard ["zip", "dmg"].contains(ext) else { return false }
            if badWords.contains(where: { n.contains($0.lowercased()) }) { return false }
            if let size = a.size, size < 40_000 { return false }
            return true
        }
        guard !usable.isEmpty else { return nil }

        if let pattern = manifest?.asset, !pattern.isEmpty {
            if let hit = usable.first(where: { fnmatch(pattern, $0.name, 0) == 0 }) { return hit }
            // 允许写成子串
            if let hit = usable.first(where: { $0.name.localizedCaseInsensitiveContains(pattern) }) { return hit }
        }

        func score(_ a: GHAsset) -> Int {
            let n = a.name.lowercased()
            var s = 0
            if n.hasSuffix(".zip") { s += 6 }
            if n.hasSuffix(".dmg") { s += 4 }
            if n.contains("mac") || n.contains("macos") || n.contains("osx") { s += 4 }
            if n.contains("universal") { s += 3 }
            if n.contains("arm64") || n.contains("aarch64") { s += 2 }
            if n.contains("x86") || n.contains("intel") { s -= 1 }
            if n.contains("app") { s += 2 }
            if n.contains("lite") || n.contains("demo") { s -= 2 }
            if a.size ?? 0 > 2_000_000 { s += 1 }
            return s
        }
        return usable.max { score($0) < score($1) }
    }
}

// MARK: - 解析器

public enum ImportResolver {

    public static func inspect(_ raw: String, token: String? = nil) async throws -> ImportCandidate {
        let req = try GitHubURLParser.parse(raw)
        switch req.source {
        case .direct(let url):
            return try await inspectDirect(url, input: raw, token: token)
        case .releaseAsset(let ref, let name):
            return try await inspectRepo(ref, input: raw, token: token, preferredAsset: name)
        case .repo(let ref):
            return try await inspectRepo(ref, input: raw, token: token)
        }
    }

    private static func inspectRepo(_ ref: GitHubRepo, input: String, token: String?,
                                    preferredAsset: String? = nil) async throws -> ImportCandidate {
        let release = try await GitHubAPI.latestRelease(owner: ref.owner, repo: ref.repo,
                                                        tag: ref.tag, token: token)
        let manifest = try? await GitHubAPI.toolManifest(owner: ref.owner, repo: ref.repo,
                                                          tag: release.tag, token: token)

        let picked = preferredAsset.flatMap { name in
            release.assets.first { $0.name == name }
        } ?? AssetPicker.pick(release.assets, manifest: manifest)
        guard let asset = picked else {
            throw GitHubError.noAsset("\(ref.slug) \(release.tag)")
        }

        let version = normalizeVersion(release.tag)
        var warnings: [String] = []
        if manifest == nil {
            warnings.append("仓库里没有 akit.json，只能按 Release 文件名猜，装完会读 Info.plist 校验")
        }
        if release.prerelease == true {
            warnings.append("这是一个预发布版本（pre-release）")
        }
        if asset.name.lowercased().hasSuffix(".pkg") {
            warnings.append("PKG 需要管理员密码，A-Kit 不会代跑 sudo")
        }

        return ImportCandidate(
            id: manifest?.id ?? "\(ref.owner)/\(ref.repo)".lowercased(),
            input: input,
            owner: ref.owner,
            repo: ref.repo,
            name: manifest?.name ?? release.name ?? ref.repo,
            tagline: manifest?.tagline ?? "",
            bundleId: manifest?.bundleId ?? "",
            version: version,
            tag: release.tag,
            article: manifest?.article,
            iconURL: manifest?.icon,
            notes: release.body,
            assetName: asset.name,
            assetURL: asset.url,
            assetSize: asset.size,
            sha256: manifest?.sha256,
            supportsStatusBar: manifest?.statusBar?.supported ?? true,
            hasAKitManifest: manifest != nil,
            minOS: manifest?.minOS,
            isDirect: false,
            publishedAt: release.publishedAt,
            isPrerelease: release.prerelease ?? false,
            warnings: warnings
        )
    }

    private static func inspectDirect(_ url: URL, input: String, token: String?) async throws -> ImportCandidate {
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        guard ["zip", "dmg", "pkg"].contains(ext) else {
            throw ImportParseError.notSupported("只认 .zip / .dmg / .pkg")
        }
        var size: Int64? = nil
        if let (s, _) = try? await GitHubAPI.head(url, token: token) { size = s }

        return ImportCandidate(
            id: url.absoluteString,
            input: input,
            owner: nil, repo: nil,
            name: (name as NSString).deletingPathExtension,
            tagline: "",
            bundleId: "",
            version: "",
            tag: "",
            article: nil,
            iconURL: nil,
            notes: nil,
            assetName: name,
            assetURL: url.absoluteString,
            assetSize: size,
            sha256: nil,
            supportsStatusBar: true,
            hasAKitManifest: false,
            minOS: nil,
            isDirect: true,
            publishedAt: nil,
            isPrerelease: false,
            warnings: ["直链安装：装完从 Info.plist 读名字和版本，之后无法自动检查更新"]
        )
    }

    public static func normalizeVersion(_ tag: String) -> String {
        var v = tag.trimmingCharacters(in: .whitespaces)
        if v.hasPrefix("v") || v.hasPrefix("V") { v.removeFirst() }
        return v
    }
}
