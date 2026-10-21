import SwiftUI
import AppKit
import AKitCore
import AKitPluginKit

/// 控制台的「插件」页：左边选插件，右边是它自己的完整界面。
///
/// 右边这块不是 A-Kit 画的，是插件返回的 NSView 原样嵌进来的。
struct PluginsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    private var plugins: [LoadedPlugin] { state.pluginManager.plugins }

    private var selected: LoadedPlugin? {
        if let id = state.selectedPluginId, let p = state.pluginManager.plugin(id: id) { return p }
        return plugins.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: 208)
            Rectangle().fill(ak.border).frame(width: 0.5)
            detail
        }
    }

    // MARK: 左栏

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("插件")
                    .font(AKFont.serif(15))
                    .foregroundColor(ak.ink)
                Text("\(plugins.count)")
                    .font(AKFont.sans(10))
                    .foregroundColor(ak.inkSoft)
                Spacer()
                Button {
                    state.pluginManager.scanAndLoad()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(ak.inkSoft)
                }
                .buttonStyle(.plain)
                .help("重新扫描插件目录")
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(plugins) { p in
                        row(p)
                    }
                    if plugins.isEmpty {
                        Text("还没有插件")
                            .font(AKFont.sans(11))
                            .foregroundColor(ak.inkSoft)
                            .padding(.top, 20)
                    }
                    ForEach(state.pluginManager.failures, id: \.url) { f in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.url.deletingPathExtension().lastPathComponent)
                                .font(AKFont.sans(11, weight: .medium))
                                .foregroundColor(ak.accent2)
                            Text(f.message)
                                .font(AKFont.sans(9.5))
                                .foregroundColor(ak.inkSoft)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
        }
        .background(ak.bg)
    }

    private func row(_ p: LoadedPlugin) -> some View {
        let active = selected?.id == p.id
        return Button {
            state.selectedPluginId = p.id
        } label: {
            HStack(spacing: 8) {
                if let icon = p.icon {
                    Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                } else {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ak.accent.opacity(0.15))
                        .frame(width: 15, height: 15)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.record.displayName)
                        .font(AKFont.serif(12.5))
                        .foregroundColor(active ? ak.accent : ak.ink)
                        .lineLimit(1)
                    Text("v\(p.record.version)")
                        .font(AKFont.sans(9.5))
                        .foregroundColor(ak.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? ak.accent.opacity(0.09) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 右栏

    @ViewBuilder
    private var detail: some View {
        if let p = selected {
            VStack(spacing: 0) {
                header(p)
                Rectangle().fill(ak.border).frame(height: 0.5)
                PluginFullView(plugin: p)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(ak.inkSoft.opacity(0.5))
                Text("左侧还没有插件")
                    .font(AKFont.serif(13))
                    .foregroundColor(ak.inkSoft)
                Text("把 .akitplugin 放进 Plugins 目录，或者从「工具」页装一个带插件的工具")
                    .font(AKFont.sans(10.5))
                    .foregroundColor(ak.inkSoft.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ p: LoadedPlugin) -> some View {
        HStack(spacing: 10) {
            if let icon = p.icon {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(p.record.displayName)
                    .font(AKFont.serif(16))
                    .foregroundColor(ak.ink)
                Text("v\(p.record.version) · ABI \(p.record.abiVersion)\(p.record.signedTeamId.map { " · \($0)" } ?? "")")
                    .font(AKFont.sans(9.5))
                    .foregroundColor(ak.inkSoft)
            }
            Spacer()
            if let status = p.statusText, !status.isEmpty {
                Text(status)
                    .font(AKFont.sans(10.5))
                    .foregroundColor(ak.inkSoft)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
