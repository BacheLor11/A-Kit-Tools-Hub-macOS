import Foundation
import AKitPluginKit

/// 安装 / 卸载时，把工具包里的插件接进（或拔出）A-Kit。
///
/// `both` 模式下插件的物理位置是 `Xxx.app/Contents/PlugIns/Xxx.akitplugin`，
/// A-Kit 这边**建软链而不是拷贝** —— 这样 app 一更新，插件跟着更新，
/// 永远不会出现「app 是 0.5、插件是 0.4」的错位。
public enum PluginInstallBridge {

    /// app 包里的插件目录
    public static func pluginsInside(app: URL) -> [URL] {
        let dir = app.appendingPathComponent("Contents/PlugIns")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return items.filter { $0.pathExtension == "akitplugin" }
    }

    /// 把 app 里的插件软链到 A-Kit 的 Plugins 目录。返回新建的软链。
    @discardableResult
    public static func link(from app: URL, into pluginsDir: URL) throws -> [URL] {
        let found = pluginsInside(app: app)
        guard !found.isEmpty else { return [] }

        try FileManager.default.createDirectory(at: pluginsDir, withIntermediateDirectories: true)
        var made: [URL] = []

        for plugin in found {
            let link = pluginsDir.appendingPathComponent(plugin.lastPathComponent)
            // 先拆旧的（可能是悬空软链，也可能指向别的版本）
            if FileManager.default.fileExists(atPath: link.path)
                || (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                try? FileManager.default.removeItem(at: link)
            }
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: plugin)
            made.append(link)
        }
        return made
    }

    /// 卸载工具时把它的插件软链也拔掉。
    ///
    /// 只删**指向这个 app 的软链**，别人装的插件不动。
    @discardableResult
    public static func unlink(for app: URL, in pluginsDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: pluginsDir,
                                                      includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                      options: []) else { return [] }
        let appPath = app.standardizedFileURL.path
        var removed: [URL] = []
        for link in items {
            guard let target = try? fm.destinationOfSymbolicLink(atPath: link.path) else { continue }
            let resolved = target.hasPrefix("/")
                ? URL(fileURLWithPath: target).standardizedFileURL.path
                : pluginsDir.appendingPathComponent(target).standardizedFileURL.path
            if resolved.hasPrefix(appPath) {
                try? fm.removeItem(at: link)
                removed.append(link)
            }
        }
        return removed
    }

    /// 清理悬空软链（宿主 app 被手动删掉的情况）
    @discardableResult
    public static func pruneDangling(in pluginsDir: URL) -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: pluginsDir,
                                                      includingPropertiesForKeys: nil,
                                                      options: []) else { return [] }
        var removed: [URL] = []
        for link in items where link.pathExtension == "akitplugin" {
            if !fm.fileExists(atPath: link.path) {
                try? fm.removeItem(at: link)
                removed.append(link)
            }
        }
        return removed
    }
}
