import AppKit
import SwiftUI
import AKitPluginKit

/// 示例插件：把「一个工具原本的菜单栏界面」做成 A-Kit 能直接嵌入的 NSView。
///
/// 真正接入时，这里应该换成工具自己的菜单视图 —— 而且**和它独立运行时用的是同一个**，
/// 这样才不会出现「两份菜单各写一遍、必然漏项」的问题。
struct SampleMenuView: View {
    @ObservedObject var model: SampleModel
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 8) {
            HStack(spacing: 6) {
                Text("示例工具")
                    .font(.system(size: compact ? 12.5 : 14, weight: .medium))
                Text(model.status)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("实时监控", isOn: Binding(
                get: { model.monitoring },
                set: { model.setMonitoring($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: compact ? 11.5 : 12.5))

            Button("执行一次扫描") { model.scan() }
                .buttonStyle(.plain)
                .font(.system(size: compact ? 11.5 : 12.5))

            Button("打开设置…") {}
                .buttonStyle(.plain)
                .font(.system(size: compact ? 11.5 : 12.5))

            if !model.log.isEmpty {
                Text(model.log)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(compact ? 8 : 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

final class SampleModel: ObservableObject {
    @Published var monitoring = true
    @Published var status = "空闲"
    @Published var log = ""
    var host: AKPluginHost?

    func setMonitoring(_ on: Bool) {
        monitoring = on
        status = on ? "监控中" : "已暂停"
        host?.setStatusText("示例工具 · \(status)")
        host?.requestLayoutRefresh()
    }

    func scan() {
        log = "上次扫描：刚刚"
        status = "已完成"
        host?.setStatusText("示例工具 · 已完成")
        host?.requestLayoutRefresh()
    }
}

// MARK: - 插件本体

final class SamplePlugin: NSObject, AKPluginDescriptor {
    private let model = SampleModel()
    /// 宿主是弱引用：A-Kit 退出时不应该被插件拖着不放
    var host: AKPluginHost?

    var pluginId: String { "com.askb.AKitSamplePlugin" }
    var displayName: String { "示例插件" }
    var version: String { "0.1.0" }
    var abiVersion: Int32 { AKPluginABIVersion }

    func statusItemImage() -> NSImage? {
        let img = NSImage(systemSymbolName: "wrench.and.screwdriver", accessibilityDescription: "示例插件")
        img?.isTemplate = true
        return img
    }

    func makePanelView(width: CGFloat) -> NSView {
        model.host = host
        let v = NSHostingView(rootView: SampleMenuView(model: model, compact: true))
        v.frame = NSRect(x: 0, y: 0, width: width, height: panelHeight(width: width))
        return v
    }

    func panelHeight(width: CGFloat) -> CGFloat {
        // 内容变了就多要一点高度；真实工具按自己内容算
        model.log.isEmpty ? 102 : 122
    }

    func makePopoverView(width: CGFloat) -> NSView? { nil }

    func makeFullView() -> NSView {
        model.host = host
        let v = NSHostingView(rootView: SampleMenuView(model: model, compact: false))
        v.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        return v
    }

    func statusText() -> String? { "示例工具 · \(model.status)" }

    func activate() {
        model.host = host
        host?.setStatusText("示例工具 · \(model.status)")
    }

    func deactivate() {}
}

// MARK: - 入口

@_cdecl("akit_plugin_main")
public func akit_plugin_main(_ hostPtr: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer? {
    let host = Unmanaged<AnyObject>.fromOpaque(hostPtr).takeUnretainedValue() as? AKPluginHost
    let plugin = SamplePlugin()
    plugin.host = host
    return Unmanaged.passRetained(plugin).toOpaque()
}
