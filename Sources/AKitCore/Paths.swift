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
    public static var backups: URL { support.appendingPathComponent("Backups", isDirectory: true) }
    public static var downloads: URL { support.appendingPathComponent("Downloads", isDirectory: true) }
    public static var logs: URL { support.appendingPathComponent("Logs", isDirectory: true) }

    public static func ensure() {
        for dir in [support, backups, downloads, logs] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    public static func expand(_ path: String) -> URL {
        let expanded = NSString(string: path).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }
}
