import SwiftUI
import AppKit
import AKitCore
import AKitStatusKit
import AKitPluginKit

/// 内容自然高度的上报通道。
///
/// ScrollView 不会把内容高度算进 `fittingSize`，所以宿主永远贴合不准。
/// 这里让内层内容自己量一次，外层按量到的值设高度 —— 这样「面板跟随内容长高」
/// 才成立，也就不用一直挂着滚动条。
private struct PanelContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 状态栏点开的面板（不是长菜单，是卡片式面板）
struct PanelView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var onOpenConsole: () -> Void
    var onShowMenu: (String) -> Void
    var onOpenPage: (String) -> Void = { _ in }
    var onQuit: () -> Void
    var onSettings: () -> Void
    /// 宿主给的宽度：取所有工具的需求最大值，最小 336
    var width: CGFloat = 336
    /// 内容尺寸变了 → 请宿主重新贴合面板（宽高都跟随内容）
    var onLayoutChange: () -> Void = {}

    @State private var query = ""
    /// 哪些卡片是展开的（点一下就切，暂时只在本次会话里记）
    /// 快照模式可用 AKIT_SNAPSHOT_EXPAND=<工具 id> 指定初始展开项，方便验证界面
    @State private var expanded: Set<String> = {
        guard let id = ProcessInfo.processInfo.environment["AKIT_SNAPSHOT_EXPAND"], !id.isEmpty
        else { return [] }
        return [id]
    }()
    @State private var didPrimeExpansion = false
    /// 卡片内容量出来的自然高度
    @State private var measuredHeight: CGFloat = 0

    /// 卡片宽度跟着面板宽度走，不再写死 316
    private var cardWidth: CGFloat { width - 20 }

    /// 列表最多能长到多高：屏幕可用高度扣掉头尾和边距。
    /// 超过这个高度才允许滚动 —— 日常工具都够不着这条线。
    private var maxListHeight: CGFloat {
        let visible = NSScreen.main?.visibleFrame.height ?? 900
        return max(240, visible - 210)
    }

    /// 当前列表高度：还没量到时先给个保守值，量到之后紧跟内容
    private var listHeight: CGFloat {
        measuredHeight <= 0 ? 120 : min(measuredHeight, maxListHeight)
    }

    private var scrolls: Bool { measuredHeight > maxListHeight + 0.5 }

    // MARK: 数据

    /// 面板里的卡片 = 实体列表，跟「工具」页同一份数据。
    ///
    /// 有插件的能展开它自己的界面，没有的只有一行状态 + 打开。
    /// 不再分成「插件」和「其他工具」两组。
    private var cards: [ToolEntity] {
        var list = state.entities.filter {
            $0.isInstalled || $0.plugin != nil || $0.legacy != nil
        }
        list = list.filter { state.layout.display(for: $0.layoutId) != .hidden }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { $0.name.lowercased().contains(q) }
    }

    private var totalCount: Int {
        state.entities.filter { $0.isInstalled || $0.plugin != nil || $0.legacy != nil }.count
    }

    // MARK: 布局

    var body: some View {
        VStack(spacing: 0) {
            header
            if totalCount > 4 { searchRow }
            // 高度由内容决定：量到多高就多高，只有超过屏幕才退化成滚动。
            // 以前这里是固定 maxHeight: 520，一展开菜单就被裁 / 出滚动条。
            ScrollView(.vertical, showsIndicators: scrolls) {
                VStack(spacing: 6) {
                    if cards.isEmpty {
                        Text("没有显示中的工具")
                            .font(AKFont.sans(12))
                            .foregroundColor(ak.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 14)
                            .padding(.horizontal, 14)
                    }

                    ForEach(cards) { entity in
                        EntityCard(state: state,
                                   entity: entity,
                                   width: cardWidth,
                                   expanded: expansionBinding(entity.id),
                                   onShowMenu: onShowMenu,
                                   onOpenPage: onOpenPage)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: PanelContentHeightKey.self, value: g.size.height)
                    }
                )
            }
            .frame(height: listHeight)
            .scrollDisabled(!scrolls)

            footer
        }
        .frame(width: width)
        .background(ak.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ak.border, lineWidth: 0.5)
        )
        .onAppear(perform: primeExpansion)
        .onChange(of: state.focusPluginId) { _ in primeExpansion() }
        .onPreferenceChange(PanelContentHeightKey.self) { h in
            guard abs(h - measuredHeight) > 0.5 else { return }
            measuredHeight = h
            // 高度变了：让宿主把 NSPanel 重新贴合一次
            DispatchQueue.main.async { onLayoutChange() }
        }
    }

    /// 第一次打开：展开第一个有界面的卡片，避免用户看到的还是"摘要"。
    /// 从菜单栏图标点进来的：只展开它，其余收起。
    private func primeExpansion() {
        if let focus = state.focusPluginId,
           state.pluginManager.plugin(id: focus) != nil {
            expanded = [focus]
            return
        }
        guard !didPrimeExpansion else { return }
        didPrimeExpansion = true
        // 用户配了「默认展开」的先摊开（插件界面或老协议菜单都算）
        for e in state.entities where state.layout.display(for: e.layoutId) == .expanded {
            expanded.insert(e.id)
        }
        if expanded.isEmpty, let first = state.entities.first(where: { $0.plugin != nil }) {
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
