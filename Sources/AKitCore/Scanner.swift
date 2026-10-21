import AppKit
import Foundation

public enum Scanner {
    /// 扫描目录下的 .app，按 bundle 前缀 + 清单里登记的 bundleId 过滤。
    public static func scan(settings: AKSettings, knownBundleIds: Set<String> = []) -> [InstalledApp] {
        var result: [InstalledApp] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for dir in settings.scanDirectories {
            let url = AKPaths.expand(dir)
            guard let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles]) else { continue }
            for child in children where child.pathExtension == "app" {
                guard let app = readApp(at: child) else { continue }
                let matched = knownBundleIds.contains(app.bundleId)
                    || settings.bundlePrefixes.contains { !$0.isEmpty && app.bundleId.hasPrefix($0) }
                guard matched, !seen.contains(app.bundleId) else { continue }
                seen.insert(app.bundleId)
                result.append(app)
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public static func readApp(at url: URL) -> InstalledApp? {
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? ""
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return InstalledApp(bundleId: bundleId, name: name, version: version, build: build,
                            path: url,
                            sizeBytes: 0,
                            modified: attrs?[.modificationDate] as? Date)
    }

    /// 单独算体积（只在需要展示时调，避免打开页面就扫全盘）
    public static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileAllocatedSizeKey, .isRegularFileKey]) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: [.fileAllocatedSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileAllocatedSize ?? 0) }
        }
        return total
    }

    public static func isRunning(bundleId: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }
}
