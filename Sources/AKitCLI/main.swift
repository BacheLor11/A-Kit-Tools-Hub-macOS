import Foundation
import AKitCore

// akit —— 和图形界面共用同一套 registry / 安装器

let args = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("✗ " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadManifestSync() -> Manifest? {
    let settings = AKSettings.load()
    if !settings.manifestURL.isEmpty {
        var remote: Manifest?
        let sem = DispatchSemaphore(value: 0)
        Task {
            remote = try? await ManifestStore.loadRemote(settings.manifestURL)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 15)
        if let remote { return remote }
    }
    return ManifestStore.loadCache() ?? ManifestStore.loadBundled()
}

func currentEntries() -> [ToolEntry] {
    let settings = AKSettings.load()
    let imported = ImportedStore.load()
    var tools = loadManifestSync()?.tools ?? []
    let existing = Set(tools.map(\.id))
    tools += imported.filter { !existing.contains($0.id) }.map { $0.spec() }
    let manifest: Manifest? = tools.isEmpty ? nil : Manifest(tools: tools)

    var known = Set(tools.map(\.bundleId))
    for t in imported { known.insert(t.bundleId) }
    let apps = Scanner.scan(settings: settings, knownBundleIds: known)
    return Registry.merge(manifest: manifest, installed: apps, channel: settings.channel, fallbackIds: [])
}

func humanSize(_ bytes: Int64) -> String {
    let mb = Double(bytes) / 1_048_576
    return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(bytes) / 1024)
}

func pad(_ s: String, _ n: Int) -> String {
    let count = s.count
    if count >= n { return s }
    return s + String(repeating: " ", count: n - count)
}

func installSync(_ entry: ToolEntry) {
    guard let spec = entry.spec else { fail("\(entry.name) 还没登记到清单里") }
    guard let channel = spec.channel("stable"), let urlString = channel.url, let url = URL(string: urlString) else {
        fail("\(spec.name) 没有配置下载源")
    }
    print("▸ 下载 \(spec.name) \(channel.version)")

    var downloaded: URL?
    let sem = DispatchSemaphore(value: 0)
    Task {
        downloaded = try? await Installer.download(from: url,
                                                   to: AKPaths.downloads.appendingPathComponent("\(spec.id)-\(channel.version).zip"))
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 300)
    guard let file = downloaded else { fail("下载失败") }

    if let expected = channel.sha256, !expected.isEmpty {
        let actual = (try? Installer.sha256(at: file)) ?? ""
        guard actual.lowercased() == expected.lowercased() else {
            fail("校验和不匹配\n  期望 \(expected)\n  实际 \(actual)")
        }
        print("▸ 校验通过")
    }

    do {
        let stage = AKPaths.downloads.appendingPathComponent("stage-\(spec.id)")
        let app = try Installer.unzip(file, into: stage)
        let settings = AKSettings.load()
        let dest = try Installer.install(app, into: AKPaths.expand(settings.installDirectory),
                                         backupTo: AKPaths.backups.appendingPathComponent(spec.name),
                                         expectedBundleId: spec.bundleId)
        Installer.pruneBackups(for: spec.name, root: AKPaths.backups, keep: settings.keepBackups)
        print("✓ \(spec.name) \(channel.version) → \(dest.path)")
    } catch {
        fail(error.localizedDescription)
    }
}

func usage() {
    print("""
    akit —— A-Kit 命令行

    用法：
      akit list                 列出所有工具及版本
      akit updates              只看有更新的
      akit install <id>         安装 / 更新（清单里的工具）
      akit install <url>        从 GitHub 仓库 / Release / 直链安装
      akit inspect <url>        只看解析结果，不下载
      akit imported             列出从链接装进来的工具
      akit forget <id>          忘掉某个链接安装工具的来源（不删 app）
      akit doctor               体检所有已装工具
      akit export <文件>        导出配置（换 Mac 用）
      akit import <文件>        导入配置
      akit support              打印数据目录
    """)
}

// MARK: - 链接安装

func looksLikeURL(_ s: String) -> Bool {
    s.contains("://") || s.hasPrefix("github.com/") || (s.contains("/") && !s.hasPrefix("/"))
}

func inspectSync(_ input: String) -> ImportCandidate? {
    var result: ImportCandidate?
    var failure: String?
    let sem = DispatchSemaphore(value: 0)
    let token = AKSettings.load().githubToken
    Task {
        do { result = try await ImportResolver.inspect(input, token: token) }
        catch { failure = error.localizedDescription }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 40)
    if let failure { fail(failure) }
    return result
}

func printCandidate(_ c: ImportCandidate) {
    print("  名称      \(c.name)")
    if let slug = c.slug { print("  仓库      \(slug)") }
    print("  版本      \(c.tag.isEmpty ? c.version : "\(c.tag) → \(c.version)")")
    print("  产物      \(c.assetName)  \(c.assetSize.map(humanSize) ?? "")")
    if !c.bundleId.isEmpty { print("  Bundle ID \(c.bundleId)") }
    print("  接入      \(c.hasAKitManifest ? "有 akit.json（可校验、可自动更新）" : "无自描述（装完读 Info.plist）")")
    for w in c.warnings { print("  ⚠ \(w)") }
}

func installImportSync(_ c: ImportCandidate) {
    let settings = AKSettings.load()
    var record: ImportedTool?
    var failure: String?
    let sem = DispatchSemaphore(value: 0)
    Task {
        do {
            record = try await ImportInstaller.install(
                c, into: AKPaths.expand(settings.installDirectory),
                backupRoot: AKPaths.backups) { msg in
                    print("  ▸ \(msg)")
                }
        } catch {
            failure = error.localizedDescription
        }
        sem.signal()
    }
    _ = sem.wait(timeout: .now() + 900)
    if let failure { fail(failure) }
    guard let record else { fail("安装没有完成") }
    print("✓ \(record.name) \(record.version) → \(record.installedPath ?? "")")
}

guard let command = args.first else {
    usage()
    exit(0)
}

switch command {
case "list", "ls":
    let entries = currentEntries()
    guard !entries.isEmpty else { print("没有工具"); exit(0) }
    print(pad("ID", 26) + pad("名称", 22) + pad("版本", 12) + "状态")
    print(String(repeating: "─", count: 74))
    for e in entries {
        let version = e.installed?.displayVersion ?? "-"
        var status = e.isInstalled ? "已安装" : "未安装"
        if e.updateAvailable { status = "可更新 → \(e.latest?.version ?? "")" }
        print(pad(e.id, 26) + pad(e.name, 22) + pad(version, 12) + status)
    }

case "updates":
    let ups = currentEntries().filter { $0.updateAvailable }
    if ups.isEmpty { print("都是最新的") }
    for e in ups {
        print("\(e.name): \(e.installed?.version ?? "?") → \(e.latest?.version ?? "?")")
    }

case "install", "update":
    guard args.count > 1 else { fail("缺工具 id 或链接，用 akit help 看用法") }
    let target = args[1]
    if looksLikeURL(target) {
        guard let c = inspectSync(target) else { fail("解析失败") }
        print("▸ 解析到：")
        printCandidate(c)
        if c.needsSudo { fail("PKG 需要管理员密码，请手动安装") }
        installImportSync(c)
    } else {
        guard let entry = currentEntries().first(where: { $0.id == target || $0.name.lowercased() == target.lowercased() }) else {
            fail("找不到工具 \(target)")
        }
        installSync(entry)
    }

case "inspect":
    guard args.count > 1 else { fail("用法：akit inspect <url>") }
    guard let c = inspectSync(args[1]) else { fail("解析失败") }
    printCandidate(c)
    if let notes = c.notes, !notes.isEmpty {
        print("\n更新说明：")
        print(notes.split(separator: "\n").prefix(12).joined(separator: "\n"))
    }

case "imported":
    let list = ImportedStore.load()
    guard !list.isEmpty else { print("还没有从链接装过工具"); exit(0) }
    print(pad("名称", 24) + pad("版本", 12) + pad("来源", 34) + "产物")
    print(String(repeating: "─", count: 96))
    for t in list {
        print(pad(t.name, 24) + pad(t.version, 12) + pad(t.slug ?? "直链", 34) + t.assetName)
    }

case "forget":
    guard args.count > 1 else { fail("用法：akit forget <id>") }
    let id = args[1]
    let before = ImportedStore.load()
    guard before.contains(where: { $0.id == id || $0.name.lowercased() == id.lowercased() }) else {
        fail("没有这个来源记录")
    }
    ImportedStore.save(before.filter { $0.id != id && $0.name.lowercased() != id.lowercased() })
    print("✓ 已忘掉 \(id) 的来源（app 没有删）")

case "doctor":
    let entries = currentEntries().filter { $0.isInstalled }
    if entries.isEmpty { print("没有已安装的工具") }
    var problems = 0
    for e in entries {
        guard let app = e.installed else { continue }
        let h = Health.check(app)
        let size = Scanner.directorySize(app.path)
        print("\n\(e.name)  \(app.displayVersion)  \(humanSize(size))")
        print("  签名      \(h.signer)")
        print("  公证      \(h.notarized ? "是" : "否")   Gatekeeper: \(h.gatekeeper)")
        print("  架构      \(h.architectures.joined(separator: "/"))")
        print("  最低系统  \(h.minOS)")
        if h.warnings.isEmpty {
            print("  ✓ 没问题")
        } else {
            problems += h.warnings.count
            for w in h.warnings { print("  ⚠ \(w)") }
        }
    }
    if problems > 0 { exit(2) }

case "export":
    guard args.count > 1 else { fail("用法：akit export <文件路径>") }
    let settings = AKSettings.load()
    let layout = AKLayout.load()
    let bundle: [String: Any] = [
        "version": 1,
        "exportedAt": ISO8601DateFormatter().string(from: Date()),
        "settings": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))) ?? [:],
        "layout": (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(layout))) ?? [:],
    ]
    let data = try! JSONSerialization.data(withJSONObject: bundle, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath))
    print("✓ 已导出 \(args[1])")

case "import":
    guard args.count > 1 else { fail("用法：akit import <文件路径>") }
    let url = URL(fileURLWithPath: NSString(string: args[1]).expandingTildeInPath)
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        fail("读不了这个文件")
    }
    if let s = obj["settings"] as? [String: Any],
       let sd = try? JSONSerialization.data(withJSONObject: s),
       let settings = try? JSONDecoder().decode(AKSettings.self, from: sd) {
        settings.save()
        print("✓ 设置已导入")
    }
    if let l = obj["layout"] as? [String: Any],
       let ld = try? JSONSerialization.data(withJSONObject: l),
       let layout = try? JSONDecoder().decode(AKLayout.self, from: ld) {
        layout.save()
        print("✓ 菜单栏布局已导入")
    }

case "support":
    AKPaths.ensure()
    print(AKPaths.support.path)

case "help", "-h", "--help":
    usage()

default:
    fail("未知命令 \(command)，试试 akit help")
}
