import SwiftUI
import AppKit
import AKitCore

/// 只有插件、没有独立 app 的工具，在「工具」列表里长这样。
///
/// 它和普通工具是同一张列表的同一行，只是左边标「仅插件」、右边没有「打开 app」。
struct PluginOnlyRow: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    var entity: ToolEntity
    @State private var hovered = false
    @State private var confirmRemove = false

    private var plugin: LoadedPlugin? { entity.plugin }

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 5) {
                AKMeta(text: "仅插件", color: ak.accent2)
                Text("v\(plugin?.record.version ?? "—")")
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft)
                Text("ABI \(plugin?.record.abiVersion ?? 0)")
                    .font(AKFont.sans(10.5))
                    .foregroundColor(ak.inkSoft.opacity(0.65))
            }
            .frame(width: 96, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(entity.name)
                    .font(AKFont.serif(19))
                    .foregroundColor(hovered ? ak.accent : ak.ink)
                HStack(spacing: 5) {
                    AKTag(text: "无独立 app")
                    if let s = plugin?.statusText, !s.isEmpty {
                        AKTag(text: s)
                    }
                    if let reason = plugin?.inactiveReason {
                        AKTag(text: reason, tint: ak.accent2)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if let plugin, plugin.inactiveReason != nil {
                    Button("接管") { state.pluginManager.takeOver(pluginId: plugin.id) }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                }
                Button("打开界面") { state.selectedId = entity.id }
                    .buttonStyle(AKPrimaryButtonStyle())
                Menu {
                    Button("详情") { state.selectedId = entity.id }
                    Button("在访达中显示") {
                        if let p = plugin {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [URL(fileURLWithPath: p.record.bundlePath)])
                        }
                    }
                    Divider()
                    Button("从 A-Kit 移出…", role: .destructive) { confirmRemove = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(ak.inkSoft)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 22)
            }
            .padding(.top, 1)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture { state.selectedId = entity.id }
        .confirmationDialog("把「\(entity.name)」移出 A-Kit？", isPresented: $confirmRemove) {
            Button("移出（不动工具本体）", role: .destructive) {
                if let plugin { state.removePlugin(plugin) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会断开 A-Kit 这边的接入口；工具本体、插件文件都不删。重装工具后可以再接回来。")
        }
    }
}

/// 插件的详情：它的完整界面原样铺在这里。
struct PluginDetailSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    var plugin: LoadedPlugin
    var entity: ToolEntity
    @State private var confirmRemove = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(ak.border).frame(height: 0.5)
            PluginFullView(plugin: plugin)
        }
        .frame(width: 860, height: 580)
        .background(ak.bg)
        .confirmationDialog("把「\(entity.name)」移出 A-Kit？", isPresented: $confirmRemove) {
            Button("移出（不动工具本体）", role: .destructive) {
                state.removePlugin(plugin)
                state.selectedId = nil
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只会断开 A-Kit 这边的接入口；工具本体、插件文件都不删。")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let icon = plugin.icon {
                Image(nsImage: icon).resizable().frame(width: 22, height: 22)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name)
                    .font(AKFont.serif(18))
                    .foregroundColor(ak.ink)
                Text("v\(plugin.record.version) · ABI \(plugin.record.abiVersion)"
                     + (plugin.record.appPath == nil ? " · 无独立 app" : ""))
                    .font(AKFont.sans(10))
                    .foregroundColor(ak.inkSoft)
            }
            Spacer()
            if let s = plugin.statusText, !s.isEmpty {
                Text(s)
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft)
            }
            Button("移出 A-Kit") { confirmRemove = true }
                .buttonStyle(AKPrimaryButtonStyle(filled: false))
            Button("关闭") { state.selectedId = nil }
                .buttonStyle(AKPrimaryButtonStyle(filled: false))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
