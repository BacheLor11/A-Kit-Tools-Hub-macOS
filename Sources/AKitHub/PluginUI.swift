import SwiftUI
import AppKit
import AKitPluginKit

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

// MARK: - 插件卡片

struct PluginCard: View {
    @ObservedObject var plugin: LoadedPlugin
    let width: CGFloat
    @Binding var expanded: Bool
    @Environment(\.ak) private var ak
    @State private var hovered = false

    private var innerWidth: CGFloat { width - 20 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if expanded {
                Rectangle().fill(ak.border.opacity(0.5)).frame(height: 0.5)
                PluginSurface(view: plugin.panelView(width: innerWidth))
                    .frame(height: max(plugin.descriptor.panelHeight(width: innerWidth), 20))
                    .padding(.vertical, 2)
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
            withAnimation(.easeOut(duration: 0.14)) { expanded.toggle() }
        } label: {
            HStack(spacing: 8) {
                iconView
                VStack(alignment: .leading, spacing: 1) {
                    Text(plugin.record.displayName)
                        .font(AKFont.serif(13.5))
                        .foregroundColor(hovered ? ak.accent : ak.ink)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Circle().fill(Color.green.opacity(0.8)).frame(width: 4, height: 4)
                        Text(plugin.statusText?.isEmpty == false ? plugin.statusText! : "插件")
                            .font(AKFont.sans(10))
                            .foregroundColor(ak.inkSoft)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
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

    @ViewBuilder
    private var iconView: some View {
        if let img = plugin.icon {
            Image(nsImage: img)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(ak.accent.opacity(0.15))
                .frame(width: 16, height: 16)
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
