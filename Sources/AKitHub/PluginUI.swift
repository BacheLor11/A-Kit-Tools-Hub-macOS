import SwiftUI
import AppKit
import AKitPluginKit
import AKitStatusKit

// MARK: - 把插件的 NSView 塞进 SwiftUI

/// 插件的界面是真的 NSView，不是截图也不是重绘。
/// 同一个 view 在折叠/展开之间来回移动，所以每次挂载前先摘掉旧父视图。
struct PluginSurface: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        attach(to: nsView)
    }

    private func attach(to container: NSView) {
        if view.superview !== container {
            view.removeFromSuperview()
            view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                view.topAnchor.constraint(equalTo: container.topAnchor),
                view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
    }
}

// MARK: - 工具卡片（面板里）

/// 面板里的**唯一**一种卡片。
///
/// 有插件的：点开头就地展开它自己的界面。
/// 没插件的（纯 app / 老协议）：只有一行状态 + 打开按钮，不给假界面。
/// 不再分「插件卡」和「其他工具」两组 —— 它们本来就是同一份列表。
struct EntityCard: View {
    @ObservedObject var state: AppState
    var entity: ToolEntity
    let width: CGFloat
    @Binding var expanded: Bool
    /// 面板里的「⋯」：弹出工具的原生菜单
    var onShowMenu: (String) -> Void = { _ in }
    /// 打开这个工具的整页界面（插件形态才有）
    var onOpenPage: (String) -> Void = { _ in }
    @Environment(\.ak) private var ak
    @State private var hovered = false

    private var plugin: LoadedPlugin? { entity.plugin }
    /// 老协议工具上报的菜单项（A-Key-Stats 这类）
    private var legacyMenu: [AKMenuItem] { entity.legacy?.menu ?? [] }
    /// 有插件界面，或者有可展示的菜单项，就能展开
    private var canExpand: Bool { plugin != nil || !legacyMenu.isEmpty }
    private var innerWidth: CGFloat { width - 20 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Rectangle().fill(ak.border.opacity(0.5)).frame(height: 0.5)
                if let plugin {
                    PluginSurface(view: plugin.panelView(width: innerWidth))
                        .frame(height: max(plugin.descriptor.panelHeight(width: innerWidth), 20))
                        .padding(.vertical, 2)
                } else if !legacyMenu.isEmpty {
                    ToolMenuList(items: legacyMenu, dense: true) { itemId in
                        if let bundleId = entity.legacy?.bundleId {
                            state.invoke(toolId: bundleId, itemId: itemId)
                        }
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(expanded ? ak.surface : ak.surface.opacity(hovered ? 0.9 : 0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ak.border.opacity(expanded || hovered ? 1 : 0.6), lineWidth: 0.5)
        )
        .onHover { hovered = $0 }
    }

    private var header: some View {
        Button {
            guard canExpand else {
                if let entry = entity.entry { state.open(entry) }
                return
            }
            withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                iconView
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(entity.name)
                            .font(AKFont.serif(13.5))
                            .foregroundColor(hovered ? ak.accent : ak.ink)
                            .lineLimit(1)
                        if entity.pluginDisabled {
                            Text("已禁用")
                                .font(AKFont.sans(9))
                                .foregroundColor(ak.inkSoft)
                        }
                        if plugin == nil, !legacyMenu.isEmpty {
                            Text("\(legacyMenu.filter { $0.kind != .separator }.count) 项")
                                .font(AKFont.sans(9))
                                .foregroundColor(ak.inkSoft.opacity(0.8))
                        }
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(dotColor)
                            .frame(width: 4, height: 4)
                        Text(entity.subtitle)
                            .font(AKFont.sans(10))
                            .foregroundColor(ak.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)

                if let reason = plugin?.inactiveReason {
                    Button("接管") { state.pluginManager.takeOver(pluginId: entity.id) }
                        .buttonStyle(.plain)
                        .font(AKFont.sans(9.5, weight: .medium))
                        .foregroundColor(ak.accent2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(ak.accent2.opacity(0.5), lineWidth: 0.5)
                        )
                        .help(reason)
                }

                if let plugin {
                    Button {
                        onOpenPage(plugin.id)
                    } label: {
                        Image(systemName: "macwindow")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(ak.inkSoft)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("在独立窗口里打开")
                }

                if entity.legacy != nil, !legacyMenu.isEmpty {
                    Button {
                        onShowMenu(entity.id)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(ak.inkSoft)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                    .help("弹出原生菜单")
                }

                Image(systemName: canExpand ? (expanded ? "chevron.up" : "chevron.down") : "arrow.up.forward.app")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(ak.inkSoft)
                    .frame(width: 16, height: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var dotColor: Color {
        if plugin != nil { return Color.green.opacity(0.8) }
        if entity.legacy != nil { return Color.green.opacity(0.5) }
        return ak.border
    }

    @ViewBuilder
    private var iconView: some View {
        if let img = plugin?.icon {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                // app 图标带自己的圆角，不裁的话在米白底上会顶成一整块灰方块
                .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(ak.accent.opacity(0.12))
                .frame(width: 16, height: 16)
                .overlay(
                    Image(systemName: "app")
                        .font(.system(size: 9))
                        .foregroundColor(ak.inkSoft)
                )
        }
    }
}

// MARK: - 插件的完整界面（控制台里的整页）

struct PluginFullView: View {
    @ObservedObject var plugin: LoadedPlugin
    var body: some View {
        PluginSurface(view: plugin.fullView())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
