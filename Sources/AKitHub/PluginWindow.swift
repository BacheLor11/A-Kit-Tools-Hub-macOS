import AppKit
import SwiftUI
import AKitCore
import AKitPluginKit

/// 插件整页界面的**独立窗口**。
///
/// 工具不装成独立 .app、也不占 A-Kit 控制台的一页 —— 点开就是它自己的一扇
/// 窗口，标题栏写着工具名和版本，⌘W 关掉、关掉后再点开还是原来那个实例
/// （窗口和界面都不重建，工具的状态跟着留着）。
///
/// 为什么不放进控制台侧栏：用户明确要的是「独立窗口」，塞进主界面反而把
/// A-Kit 自己的信息架构搅乱了 —— 侧栏一旦被工具页混进去，就分不清哪几页是
/// A-Kit 的、哪几页是工具的。
@MainActor
final class PluginWindows: NSObject {

    static let shared = PluginWindows()

    private var windows: [String: NSWindow] = [:]

    /// 打开（或激活已打开的）某个工具的窗口
    @discardableResult
    func show(_ plugin: LoadedPlugin) -> NSWindow {
        if let w = windows[plugin.id], w.isVisible {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return w
        }

        // 关掉过的窗口复用同一个实例：界面和插件状态都不用重建
        if let w = windows[plugin.id] {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return w
        }

        let view = plugin.fullView()
        view.autoresizingMask = [.width, .height]

        let size = Self.defaultSize
        view.frame = NSRect(origin: .zero, size: size)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = plugin.record.displayName
        w.subtitle = "v\(plugin.record.version)"
        w.contentView = view
        w.minSize = NSSize(width: 760, height: 520)
        // 自己不持有窗口生命周期，由本类管理；关掉不销毁，下次直接复用
        w.isReleasedWhenClosed = false
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .visible
        w.isMovableByWindowBackground = false
        w.tabbingMode = .disallowed
        w.collectionBehavior = [.fullScreenPrimary]
        // 记住用户拉过的尺寸与位置，按工具分别存
        w.setFrameAutosaveName("AKitPluginWindow-\(plugin.id)")
        if w.frame.size.width < 400 { w.setContentSize(size) }
        w.center()
        windows[plugin.id] = w

        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AKLogInfo("plugin", "打开工具窗口 \(plugin.record.displayName) \(plugin.record.version)")
        return w
    }

    /// 插件被移出 / 卸载 / 让位时关掉它的窗口
    func close(_ pluginId: String) {
        guard let w = windows[pluginId] else { return }
        w.orderOut(nil)
        windows[pluginId] = nil
    }

    func closeAll() {
        for (_, w) in windows { w.orderOut(nil) }
        windows.removeAll()
    }

    /// 默认窗口尺寸：贴在主屏可用区域的 76% 左右，别一开就顶天立地
    private static var defaultSize: NSSize {
        guard let screen = NSScreen.main else { return NSSize(width: 1120, height: 760) }
        let f = screen.visibleFrame
        let w = min(max(f.width * 0.76, 900), 1280)
        let h = min(max(f.height * 0.80, 620), 900)
        return NSSize(width: w.rounded(), height: h.rounded())
    }
}
