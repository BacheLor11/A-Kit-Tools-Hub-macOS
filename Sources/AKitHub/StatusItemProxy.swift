import AppKit
import AKitCore
import AKitPluginKit

/// 菜单栏代持（`hubbar`）。
///
/// 关键点：**只有 Hub 自己创建 statusItem，图标的顺序和存在才真的可控**。
/// 工具自己建的图标，顺序由各 app 的启动顺序决定，谁也管不了。
///
/// 所以每个配成 `hubbar` 的插件，这里给它单开一个 statusItem，
/// 画它的图标，点了就展开 A-Kit 面板并聚焦到它。
@MainActor
final class StatusItemProxy: NSObject {

    /// 点某个插件图标
    var onClick: ((String) -> Void)?

    private var items: [String: NSStatusItem] = [:]
    /// 上一次同步时的签名，没变就不重建（避免图标闪烁）
    private var lastSignature: String = ""

    /// 按 layout 同步菜单栏图标。全量重建，但只在签名变化时真的动。
    func sync(plugins: [LoadedPlugin], layout: AKLayout) {
        let wanted = plugins.filter { layout.slot(for: $0.record.id) == .hubbar }
        let signature = wanted.map { "\($0.record.id)@\($0.record.version)" }.joined(separator: "|")
        guard signature != lastSignature else { return }
        lastSignature = signature

        for (_, item) in items {
            NSStatusBar.system.removeStatusItem(item)
        }
        items.removeAll()

        for plugin in wanted {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                let icon = plugin.icon ?? NSImage(systemSymbolName: "puzzlepiece.extension",
                                                  accessibilityDescription: plugin.record.displayName)
                icon?.isTemplate = true
                icon?.size = NSSize(width: 17, height: 17)
                button.image = icon
                button.imagePosition = .imageOnly
                button.toolTip = plugin.record.displayName
                button.target = self
                button.action = #selector(handleClick(_:))
                button.sendAction(on: [.leftMouseUp])
            }
            items[plugin.record.id] = item
        }
        AKLogInfo("plugin", "菜单栏代持 \(items.count) 个：\(items.keys.sorted().joined(separator: ", "))")
    }

    /// 布局改了（比如用户把某个工具从 hubbar 切到 board）要强制重建
    func invalidate() {
        lastSignature = ""
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        for (id, item) in items where item.button === sender {
            onClick?(id)
            return
        }
    }
}
