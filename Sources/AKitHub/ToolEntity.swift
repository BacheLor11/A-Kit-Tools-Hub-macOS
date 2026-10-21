import Foundation
import AKitCore
import AKitStatusKit

/// **一个工具 = 安装层 + 运行层。**
///
/// 这两层来自完全不同的数据源，但必须是同一个东西：
///
/// | 层 | 来源 | 有什么 |
/// |---|---|---|
/// | 安装层 | 远程清单 + 磁盘扫描 | 装在哪、什么版本、有无新版、来源 |
/// | 运行层 | 插件 `dlopen` / 老协议 socket | 界面、落点、加载状态 |
///
/// 合并的锚点是 id：**插件约定 `pluginId == 工具 bundleId`**。
/// 匹配不上时退回路径包含判断（兼容早期没守约定的插件）。
@MainActor
struct ToolEntity: Identifiable {

    /// 形态。四种都是同一个实体，只是活着的方式不同。
    enum Form: String {
        /// 装了 app，也有插件 —— 推荐形态：A-Kit 在时接管，不在时自己跑
        case both
        /// 只有插件，没有独立 app —— 只能活在 A-Kit 里
        case pluginOnly
        /// 只有 app，没有插件 —— 老工具，面板里只能「打开」
        case appOnly
        /// 只靠老协议在线，清单和扫描都没收录
        case legacy

        var label: String {
            switch self {
            case .both: return "双形态"
            case .pluginOnly: return "仅插件"
            case .appOnly: return "独立 app"
            case .legacy: return "老协议"
            }
        }
    }

    /// 统一主键：优先 bundleId，没有就用清单 id
    let id: String
    var name: String
    var entry: ToolEntry?
    var plugin: LoadedPlugin?
    var legacy: AKToolInfo?
    /// 插件存在但被用户禁用 / 崩溃哨兵禁用
    var pluginDisabled: Bool = false

    var form: Form {
        if entry != nil && plugin != nil { return .both }
        if entry == nil && plugin != nil { return .pluginOnly }
        if entry != nil { return .appOnly }
        return .legacy
    }

    var isInstalled: Bool { entry?.isInstalled == true }
    /// 能在面板里展开完整界面
    var hasSurface: Bool { plugin != nil }
    var version: String? {
        plugin?.record.version ?? entry?.installed?.version
    }
    var updateAvailable: Bool { entry?.updateAvailable == true }

    /// 折叠态那一行字
    var subtitle: String {
        if let text = plugin?.statusText, !text.isEmpty { return text }
        if let status = legacy?.status, !status.isEmpty { return status }
        if pluginDisabled { return "插件已禁用" }
        if let v = version { return "v\(v)" }
        return isInstalled ? "已安装" : "未接入"
    }
}

// MARK: - 合并

@MainActor
enum ToolEntityIndex {

    /// 把安装层和运行层合成一份实体列表。
    ///
    /// 顺序：有插件的排前面（它们才是 A-Kit 真正能管起来的），其余按名字排。
    static func merge(entries: [ToolEntry],
                      plugins: [LoadedPlugin],
                      connected: [String: AKToolInfo],
                      isDisabled: (String) -> Bool) -> [ToolEntity] {

        var result: [ToolEntity] = []
        var usedPluginIds = Set<String>()

        for entry in entries {
            let bundleId = entry.installed?.bundleId ?? entry.id

            // ① 主键相等：pluginId 按约定等于 bundleId
            var matched = plugins.first {
                !usedPluginIds.contains($0.id) && ($0.record.id == bundleId || $0.record.id == entry.id)
            }

            // ② 退路：插件住在 app 里，路径能对上
            if matched == nil, let appPath = entry.installed?.path.path {
                matched = plugins.first { p in
                    guard !usedPluginIds.contains(p.id), let pluginApp = p.record.appPath else { return false }
                    return appPath.hasPrefix(pluginApp) || pluginApp.hasPrefix(appPath)
                }
            }

            if let matched { usedPluginIds.insert(matched.id) }

            result.append(ToolEntity(
                id: bundleId,
                name: entry.name,
                entry: entry,
                plugin: matched,
                legacy: connected[bundleId],
                pluginDisabled: matched == nil && isDisabled(bundleId)
            ))
        }

        // 只在插件里出现的（没有独立 app，或者 app 没被扫描到）
        for p in plugins where !usedPluginIds.contains(p.id) {
            result.append(ToolEntity(
                id: p.record.id,
                name: p.record.displayName,
                entry: nil,
                plugin: p,
                legacy: connected[p.record.id],
                pluginDisabled: false
            ))
        }

        // 只靠老协议在线、清单和扫描都没收录的
        let knownIds = Set(result.map(\.id))
        for (bundleId, info) in connected where !knownIds.contains(bundleId) {
            let entry = entries.first { $0.isRuntimeOnly && $0.id == bundleId }
            if entry != nil { continue }   // 已经作为 runtimeOnly entry 进过循环
            result.append(ToolEntity(
                id: bundleId,
                name: info.name,
                entry: nil,
                plugin: nil,
                legacy: info,
                pluginDisabled: false
            ))
        }

        return result.sorted { a, b in
            if a.hasSurface != b.hasSurface { return a.hasSurface }
            if a.isInstalled != b.isInstalled { return a.isInstalled }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}
