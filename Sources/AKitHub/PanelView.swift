import SwiftUI
import AppKit
import AKitCore
import AKitStatusKit

/// 状态栏点开的面板（不是长菜单，是卡片式面板）
struct PanelView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var onOpenConsole: () -> Void
    var onShowMenu: (String) -> Void
    var onQuit: () -> Void
    var onSettings: () -> Void

    @State private var query = ""

    private var visible: [ToolEntry] {
        var list = state.entries.filter { $0.isInstalled && !state.layout.isHidden($0.id) }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        // 接入的排前面
        return list.sorted { a, b in
            if state.isConnected(a) != state.isConnected(b) { return state.isConnected(a) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if state.entries.filter({ $0.isInstalled }).count > 4 {
                searchRow
            }
            ScrollView {
                VStack(spacing: 6) {
                    if visible.isEmpty {
                        Text("没有显示中的工具")
                            .font(AKFont.sans(12))
                            .foregroundColor(ak.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 14)
                    }
                    ForEach(visible) { entry in
                        ToolCard(entry: entry, onShowMenu: onShowMenu)
                            .environmentObject(state)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .frame(height: min(CGFloat(max(visible.count, 1)) * 56 + 12, 372))

            footer
        }
        .frame(width: 336)
        .background(ak.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ak.border, lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("A-Kit")
                .font(.custom("Zapfino", size: 12))
                .foregroundColor(ak.ink)
            Text("\(state.connected.count) 在线")
                .font(AKFont.sans(10))
                .foregroundColor(ak.inkSoft)
            Spacer()
            Button {
                onOpenConsole()
            } label: {
                Text("控制台")
                    .font(AKFont.sans(11, weight: .medium))
                    .foregroundColor(ak.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 9)
    }

    private var searchRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundColor(ak.inkSoft.opacity(0.6))
            TextField("搜索", text: $query)
                .textFieldStyle(.plain)
                .font(AKFont.sans(11.5))
                .foregroundColor(ak.ink)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(ak.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ak.border, lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(ak.border).frame(height: 0.5)
            HStack(spacing: 12) {
                Button("检查更新") {
                    Task { await state.checkUpdates(silent: false) }
                }
                .buttonStyle(.plain)
                .font(AKFont.sans(11))
                .foregroundColor(ak.inkSoft)
                Button("设置") { onSettings() }
                    .buttonStyle(.plain)
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft)
                Spacer()
                Button("退出") { onQuit() }
                    .buttonStyle(.plain)
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

private struct ToolCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    var entry: ToolEntry
    var onShowMenu: (String) -> Void
    @State private var hovered = false

    private var bundleId: String { entry.installed?.bundleId ?? entry.spec?.bundleId ?? entry.id }
    private var info: AKToolInfo? { state.connected[bundleId] }

    /// 卡片上平铺的常用项：取工具菜单里前 3 个可直接点击的项
    private var quickItems: [AKMenuItem] {
        guard let info else { return [] }
        return Array(info.menu.filter {
            ($0.kind == .toggle || $0.kind == .item) && $0.enabled && ($0.children == nil || $0.children!.isEmpty)
        }.prefix(2))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(AKFont.serif(13.5))
                    .foregroundColor(hovered ? ak.accent : ak.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle()
                        .fill(info == nil ? ak.border : Color.green.opacity(0.8))
                        .frame(width: 4, height: 4)
                    Text(info?.status ?? (info == nil ? "未接入" : "已接入"))
                        .font(AKFont.sans(10))
                        .foregroundColor(ak.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)

            ForEach(quickItems) { item in
                Button {
                    state.invoke(toolId: bundleId, itemId: item.id)
                } label: {
                    Text(item.title)
                        .font(AKFont.sans(10.5, weight: .medium))
                        .foregroundColor(item.checked == true ? ak.bg : ak.accent)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(item.checked == true ? ak.accent : ak.accent.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }

            Button {
                onShowMenu(bundleId)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ak.inkSoft)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)

            Button {
                state.open(entry)
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(ak.inkSoft)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovered ? ak.surface : ak.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ak.border.opacity(hovered ? 1 : 0.6), lineWidth: 0.5)
        )
        .onHover { hovered = $0 }
    }
}
