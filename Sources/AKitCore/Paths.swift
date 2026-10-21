import Foundation

/// A-Kit 所有运行期数据的落盘位置，统一在这里定义。
public enum AKPaths {
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("A-Kit", isDirectory: true)
    }

    public static var socket: URL { support.appendingPathComponent("hub.sock") }
    public static var manifestCache: URL { support.appendingPathComponent("manifest.cache.json") }
    public static var settingsFile: URL { support.appendingPathComponent("settings.json") }
    public static var layoutFile: URL { support.appendingPathComponent("layout.json") }
    public static var usageFile: URL { support.appendingPathComponent("usage.json") }
    /// 从 GitHub / 直链装进来的工具（带来源信息，用于检查更新）
    public static var importedFile: URL { support.appendingPathComponent("imported.json") }
    /// 本机私有的工具登记（本地源码路径、没开源的小工具）。刻意不放进仓库，
    /// 否则开源出去就把自己的目录结构也给发出去了。
    public static var localToolsFile: URL { support.appendingPathComponent("tools.local.json") }
    public static var backups: URL { support.appendingPathComponent("Backups", isDirectory: true) }
    public static var downloads: URL { support.appendingPathComponent("Downloads", isDirectory: true) }
    public static var logs: URL { support.appendingPathComponent("Logs", isDirectory: true) }
    /// 插件目录。里面放 `.akitplugin`，通常是软链指向 `xxx.app/Contents/PlugIns/…`
    public static var plugins: URL { support.appendingPathComponent("Plugins", isDirectory: true) }
    /// 插件状态（启用/禁用、崩溃次数）
    public static var pluginStateFile: URL { support.appendingPathComponent("plugin-state.json") }
    /// 崩溃哨兵：上次是否非正常退出、崩在哪个插件
    public static var crashSentinel: URL { support.appendingPathComponent("crash-sentinel.json") }

    public static func ensure() {
        for dir in [support, backups, downloads, logs, plugins] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public static func expand(_ path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}
