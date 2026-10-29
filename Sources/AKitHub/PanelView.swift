import SwiftUI
import AppKit
import AKitCore
import AKitStatusKit
import AKitPluginKit

/// 状态栏点开的面板：**左栏工具列表 + 右栏内容**，整体固定尺寸。
///
/// 为什么改成固定尺寸：以前高度跟着卡片内容长，一展开窗口就变高。
/// 顶边虽然锚住了，但整块窗口仍在屏幕上跳一下，而且 SwiftUI 的展开动画
/// 会被 NSPanel 的 setFrame 打断 —— 观感就是「一顿一顿地跳」。
/// 固定之后窗口只在弹出时定位一次，展开 / 收起 / 切换的动画全在窗口内部完成。
struct PanelView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var scheme

    var onOpenConsole: () -> Void
    var onShowMenu: (String) -> Void
    var onOpenPage: (String) -> Void = { _ in }
    var onQuit: () -> Void
    var onSettings: () -> Void
    /// 面板总宽（含左栏）
    var width: CGFloat = 640
    /// 面板总高，固定不变
    var height: CGFloat = 560

    var body: some View {
        // 主题**必须在这里注入**。
        // 以前 PanelView 没注入 `\.ak`，拿的是 EnvironmentKey 的默认值（永远浅色），
        // 系统切深色时外壳还是白的、里面的工具面板已经黑了 —— 两边对不上。
        PanelBody(state: state,
                  onOpenConsole: onOpenConsole,
                  onShowMenu: onShowMenu,
                  onOpenPage: onOpenPage,
                  onQuit: onQuit,
                  onSettings: onSettings,
                  totalWidth: width,
                  totalHeight: height)
            .environment(\.ak, AKScheme.of(scheme))
    }
}

// MARK: - 面板主体

private struct PanelBody: View {
    @ObservedObject var state: AppState
    @Environment(\.ak) private var ak

    var onOpenConsole: () -> Void
    var onShowMenu: (String) -> Void
    var onOpenPage: (String) -> Void
    var onQuit: () -> Void
    var onSettings: () -> Void
    var totalWidth: CGFloat
    var totalHeight: CGFloat

    @State private var query = ""
    @State private var expanded: Set<String> = []
    @State private var selectedId: String?
    @State private var didPrime = false

    private let navWidth: CGFloat = 186

    private var contentWidth: CGFloat { totalWidth - navWidth - 1 }

    // MARK: 数据

    /// 面板里的工具 = 实体列表，跟「工具」页同一份数据
    private var all: [ToolEntity] {
        state.entities
            .filter { $0.isInstalled || $0.plugin != nil || $0.legacy != nil }
            .filter { !$0.isHost }
            .filter { state.layout.display(for: $0.layoutId) != .hidden }
    }

    private var cards: [ToolEntity] {
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: 布局

    var body: some View {
        HStack(spacing: 0) {
            nav
                .frame(width: navWidth)
            Rectangle().fill(ak.border).frame(width: 1)
            content
                .frame(width: contentWidth)
        }
        .frame(width: totalWidth, height: totalHeight)
        .background(ak.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ak.border, lineWidth: 0.5)
        )
        .onAppear { prime() }
        .onChange(of: state.focusPluginId) { _ in prime(focus: true) }
    }

    // MARK: 左栏

    private var nav: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("A-Kit")
                    .font(.custom("Zapfino", size: 13))
                    .foregroundColor(ak.ink)
                Spacer(minLength: 2)
                Button("控制台") { onOpenConsole() }
                    .buttonStyle(.plain)
                    .font(AKFont.sans(10, weight: .medium))
                    .foregroundColor(ak.accent)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 10)

            if all.count > 5 {
                searchField
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 1) {
                    ForEach(cards) { entity in
                        PanelNavRow(
                            entity: entity,
                            icon: entity.plugin?.icon,
                            status: entity.subtitle,
                            dot: dotColor(entity),
                            selected: selectedId == entity.id,
                            online: isOnline(entity)
                        ) {
                            select(entity)
                        }
                    }
                    if cards.isEmpty {
                        Text("没有匹配的工具")
                            .font(AKFont.sans(11))
                            .foregroundColor(ak.inkSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }

            Rectangle().fill(ak.border).frame(height: 0.5)

            VStack(alignment: .leading, spacing: 6) {
                navAction("检查更新") { Task { await state.checkUpdates(silent: false) } }
                navAction("设置") { onSettings() }
                navAction("退出 A-Kit") { onQuit() }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(ak.surface.opacity(0.35))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 9.5))
                .foregroundColor(ak.inkSoft.opacity(0.6))
            TextField("搜索工具", text: $query)
                .textFieldStyle(.plain)
                .font(AKFont.sans(11))
                .foregroundColor(ak.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(ak.surface))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(ak.border, lineWidth: 0.5))
    }

    private func navAction(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(AKFont.sans(11))
                .foregroundColor(ak.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 右栏

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 6) {
                    ForEach(cards) { entity in
                        EntityCard(state: state,
                                   entity: entity,
                                   width: contentWidth - 24,
                                   expanded: expansionBinding(entity.id),
                                   onShowMenu: onShowMenu,
                                   onOpenPage: onOpenPage)
                            .id(entity.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .onChange(of: selectedId) { id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.26)) {
                    proxy.scrollTo(id, anchor: .top)
                }
            }
        }
        .background(ak.bg)
    }

    // MARK: 交互

    private func select(_ entity: ToolEntity) {
        selectedId = entity.id
        withAnimation(.easeInOut(duration: 0.2)) {
            expanded = [entity.id]
        }
    }

    /// 第一次打开：选中并展开一个工具，避免右侧空着
    private func prime(focus: Bool = false) {
        if let focusId = state.focusPluginId,
           let e = all.first(where: { $0.plugin?.id == focusId || $0.id == focusId }) {
            selectedId = e.id
            expanded = [e.id]
            return
        }
        guard !didPrime else { return }
        didPrime = true
        // 用户配了「默认展开」的先摊开
        let wanted = all.filter { state.layout.display(for: $0.layoutId) == .expanded }
        if !wanted.isEmpty {
            expanded = Set(wanted.map(\.id))
            selectedId = wanted.first?.id
            return
        }
        if let first = all.first(where: { $0.plugin != nil }) ?? all.first {
            expanded = [first.id]
            selectedId = first.id
        }
    }

    private func expansionBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(id) },
            set: { on in
                withAnimation(.easeInOut(duration: 0.2)) {
                    if on {
                        expanded.insert(id)
                        selectedId = id
                    } else {
                        expanded.remove(id)
                    }
                }
            }
        )
    }

    private func isOnline(_ entity: ToolEntity) -> Bool {
        if entity.plugin?.isActive == true { return true }
        return entity.legacy != nil
    }

    private func dotColor(_ entity: ToolEntity) -> Color {
        if entity.plugin?.isActive == true { return Color.green.opacity(0.85) }
        if entity.legacy != nil { return Color.green.opacity(0.85) }
        if entity.plugin?.inactiveReason != nil { return ak.accent2.opacity(0.85) }
        return ak.border
    }
}

// MARK: - 左栏的一行

private struct PanelNavRow: View {
    @Environment(\.ak) private var ak
    var entity: ToolEntity
    var icon: NSImage?
    var status: String
    var dot: Color
    var selected: Bool
    var online: Bool
    var action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Group {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 15, height: 15)
                            .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 10))
                            .foregroundColor(ak.inkSoft)
                            .frame(width: 15)
                    }
                }
                Text(entity.name)
                    .font(AKFont.sans(12, weight: selected ? .medium : .regular))
                    .foregroundColor(selected ? ak.accent : ak.ink)
                    .lineLimit(1)
                Spacer(minLength: 3)
                Circle().fill(dot).frame(width: 4.5, height: 4.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? ak.surface : (hovered ? ak.surface.opacity(0.65) : Color.clear))
            )
            .overlay(alignment: .leading) {
                // 选中态的左侧竖条，比整块变色更安静
                RoundedRectangle(cornerRadius: 1)
                    .fill(ak.accent)
                    .frame(width: 2, height: 12)
                    .opacity(selected ? 1 : 0)
                    .offset(x: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(status)
    }
}
