import SwiftUI
import AKitStatusKit

/// 把工具上报的菜单**原样**铺出来。
///
/// 设计原则：不裁、不合并、不省略 —— 工具上报多少条就画多少条，
/// 分隔线、分组标题、勾选状态、禁用项、子菜单全部保留。
/// 面板、菜单栏页、状态栏菜单都复用这一份，避免三处显示不一致。
struct ToolMenuList: View {
    var items: [AKMenuItem]
    var onInvoke: (String) -> Void
    /// 面板里用紧凑一点的字号
    var dense: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                ToolMenuRow(item: item, depth: 0, dense: dense, onInvoke: onInvoke)
            }
        }
    }
}

/// 单条菜单。子菜单递归铺在同一列里（缩进），这样面板窄也不怕。
private struct ToolMenuRow: View {
    @Environment(\.ak) private var ak

    var item: AKMenuItem
    var depth: Int
    var dense: Bool
    var onInvoke: (String) -> Void

    var body: some View {
        switch item.kind {
        case .separator:
            Rectangle()
                .fill(ak.border.opacity(0.7))
                .frame(height: 0.5)
                .padding(.vertical, 3)
                .padding(.leading, CGFloat(depth) * 10)

        case .header:
            Text(item.title)
                .font(AKFont.sans(9.5, weight: .semibold))
                .foregroundColor(ak.inkSoft.opacity(0.7))
                .padding(.leading, 8 + CGFloat(depth) * 10)
                .padding(.top, 4)
                .padding(.bottom, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .item, .toggle:
            Button {
                if item.enabled { onInvoke(item.id) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: (item.kind == .toggle && (item.checked ?? false)) ? "checkmark" : "minus")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundColor(item.kind == .toggle && (item.checked ?? false) ? ak.accent : .clear)
                        .frame(width: 9)

                    Text(item.title)
                        .font(AKFont.sans(dense ? 11 : 11.5))
                        .foregroundColor(item.enabled ? ak.ink : ak.inkSoft.opacity(0.4))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    if let s = item.shortcut, !s.isEmpty {
                        Text(s)
                            .font(AKFont.mono(9.5))
                            .foregroundColor(ak.inkSoft.opacity(0.55))
                    }
                    if let children = item.children, !children.isEmpty {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundColor(ak.inkSoft.opacity(0.5))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, dense ? 3.5 : 4)
                .padding(.leading, CGFloat(depth) * 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!item.enabled)

            if let children = item.children, !children.isEmpty {
                ForEach(children) { child in
                    ToolMenuRow(item: child, depth: depth + 1, dense: dense, onInvoke: onInvoke)
                }
            }
        }
    }
}
