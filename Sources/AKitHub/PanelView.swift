import SwiftUI
import AppKit
import AKitCore
import AKitStatusKit
import AKitPluginKit

/// 状态栏点开的面板（不是长菜单，是卡片式面板）
struct PanelView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var onOpenConsole: () -> Void
    var onShowMenu: (String) -> Void
    var onQuit: () -> Void
    var onSettings: () -> Void

    @State private var query = ""
    /// 哪些插件卡片是展开的（点一下就切，暂时只在本次会话里记）
    @State private var expanded: Set<String> = []
    @State private var didPrimeExpansion = false

    private let cardWidth: CGFloat = 316

    // MARK: 数据

    private var plugins: [LoadedPlugin] {
        var list = state.pluginManager.plugins.filter {
            state.layout.display(for: $0.record.id) != .hidden
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        list = list.filter { $0.record.displayName.lowercased().contains(q) }
        return list
    }

    /// 老协议 / 只是被扫描到、没有插件的工具
    private var legacyVisible: [ToolEntry] {
        let covered = Set(state.pluginManager.plugins.compactMap {
            $0.record.appPath.flatMap { path in
                state.entries.first { entry in
                    entry.installed?.path.path.hasPrefix(path) == true
                }?.id
            }
        })
        var list = state.allEntries.filter {
            ($0.isInstalled || $0.isRuntimeOnly)
                && !state.layout.isHidden($0.id)
                && !covered.contains($0.id)
        }
        if !query.isEmpty {
            let q = query.lowercased()
            list = list.filter { $0.name.lowercased().contains(q) }
        }
        return list.sorted { a, b in
            if state.isConnected(a) != state.isConnected(b) { return state.isConnected(a) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    private var totalCount: Int {
        state.pluginManager.plugins.count + state.allEntries.filter { $0.isInstalled || $0.isRuntimeOnly }.count
    }

    // MARK: 布局

    var body: some View {
        VStack(spacing: 0) {
            header
            if totalCount > 4 { searchRow }
                VStack(spacing: 6) {
                    if plugins.isEmpty && legacyVisible.isEmpty {
                        Text("没有显示中的工具")
                            .font(AKFont.sans(12))
                            .foregroundColor(ak.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 14)
                    }

                    ForEach(plugins) { plugin in
                        PluginCard(plugin: plugin,
                                   width: cardWidth,
                                   expanded: expansionBinding(plugin.id))
                    }

                    if !legacyVisible.isEmpty {
                        if !plugins.isEmpty {
                            HStack {
                                Text("其他工具 · 老协议")
                                    .font(AKFont.sans(9.5))
                                    .foregroundColor(ak.inkSoft.opacity(0.7))
                                Spacer()
                            }
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                        }
                        ForEach(legacyVisible) { entry in
                            ToolCard(entry: entry, onShowMenu: onShowMenu)
                                .environmentObject(state)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            .frame(maxHeight: 500, alignment: .top)

            footer
        }
        .frame(width: 336)
        .background(ak.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ak.border, lineWidth: 0.5)
        )
        .onAppear(perform: primeExpansion)
        .onChange(of: state.focusPluginId) { _ in primeExpansion() }
    }

    /// 第一次打开：展开第一个插件，避免用户看到的还是"摘要"。
    /// 从菜单栏图标点进来的：只展开它，其余收起。
    private func primeExpansion() {
        if let focus = state.focusPluginId,
           state.pluginManager.plugin(id: focus) != nil {
            expanded = [focus]
            return
        }
        guard !didPrimeExpansion else { return }
        didPrimeExpansion = true
        // 用户配了「默认展开」的先摊开
        for p in state.pluginManager.plugins where state.layout.display(for: p.record.id) == .expanded {
            expanded.insert(p.id)
        }
        if expanded.isEmpty, let first = state.pluginManager.plugins.first {
            expanded.insert(first.id)
        }
    }

    private func expansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { on in
                if on {
                    // 手风琴形态：同一时刻只展开一个
                    if state.layout.resolvedPanelStyle == .accordion {
                        expanded = [id]
                    } else {
                        expanded.insert(id)
                    }
                } else {
                    expanded.remove(id)
                }
            }
        )
    }

    // MARK: 组件

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("A-Kit")
                .font(.custom("Zapfino", size: 12))
                .foregroundColor(ak.ink)
            Text("\(state.pluginManager.plugins.count) 插件 · \(state.connected.count) 在线")
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
                Button("退出 A-Kit") { onQuit() }
                    .buttonStyle(.plain)
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }
}

// MARK: - 老协议工具的卡片

private struct ToolCard: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    var entry: ToolEntry
    var onShowMenu: (String) -> Void
    @State private var hovered = false

    private var bundleId: String { entry.installed?.bundleId ?? entry.spec?.bundleId ?? entry.id }
    private var info: AKToolInfo? { state.connected[bundleId] }

    /// 只靠 SDK 接进来、还没被清单/扫描收录
    private var unregistered: Bool { entry.isRuntimeOnly }

    private var dotColor: Color {
        if unregistered { return ak.accent2.opacity(0.8) }
        return info == nil ? ak.border : Color.green.opacity(0.8)
    }

    private var subtitle: String {
        if unregistered {
            if let s = info?.status, !s.isEmpty { return "未登记 · \(s)" }
            return "未登记"
        }
        return info?.status ?? (info == nil ? "未接入" : "已接入")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(AKFont.serif(13))
                    .foregroundColor(hovered ? ak.accent : ak.ink)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Circle().fill(dotColor).frame(width: 4, height: 4)
                    Text(subtitle)
                        .font(AKFont.sans(10))
                        .foregroundColor(ak.inkSoft)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)

            if unregistered {
                Button {
                    state.registerTool(bundleId: bundleId)
                } label: {
                    Text("登记")
                        .font(AKFont.sans(10, weight: .medium))
                        .foregroundColor(ak.accent2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(ak.accent2.opacity(0.55), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("写进本机清单 tools.local.json，下次启动也认得")
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
            .disabled(info == nil)

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
