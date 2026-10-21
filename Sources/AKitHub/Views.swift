import SwiftUI
import AppKit
import AKitCore
import AKitStatusKit

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // 跟随系统亮暗：博客那套令牌有对应的深色版本
        let ak = AKScheme.of(colorScheme)
        HStack(spacing: 0) {
            Sidebar()
            Rectangle().fill(ak.border).frame(width: 1)
            content
        }
        .background(ak.bg)
        .overlay(alignment: .bottom) { ToastOverlay() }
        .environment(\.ak, ak)
        .sheet(isPresented: $state.showImportSheet) {
            ImportSheet().environmentObject(state).environment(\.ak, ak)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.page {
        case .tools: ToolsPage()
        case .updates: UpdatesPage()
        case .menuBar: MenuBarPage()
        case .thirdParty: ThirdPartyPage()
        case .settings: SettingsPage()
        }
    }
}

// MARK: - 侧栏

private struct Sidebar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("A-Kit")
                    .font(AKFont.brand)
                    .foregroundColor(ak.ink)
                    .padding(.bottom, 2)
                Text("TOOLS HUB")
                    .font(AKFont.sans(9.5, weight: .medium))
                    .tracking(2.2)
                    .foregroundColor(ak.inkSoft.opacity(0.75))
            }
            .padding(.horizontal, 22)
            .padding(.top, 40)
            .padding(.bottom, 24)

            VStack(spacing: 2) {
                ForEach(AppState.Page.allCases) { page in
                    SidebarItem(page: page,
                                selected: state.page == page,
                                badge: page == .updates ? state.updates.count : 0) {
                        state.page = page
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(state.listening ? Color.green.opacity(0.85) : ak.accent2)
                        .frame(width: 6, height: 6)
                    Text(state.listening ? "菜单栏服务在线" : "服务未启动")
                        .font(AKFont.sans(11))
                        .foregroundColor(ak.inkSoft)
                }
                Text("\(state.installedCount) 个工具 · \(state.connected.count) 个已接入")
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft.opacity(0.8))
                Text(version)
                    .font(AKFont.sans(10))
                    .foregroundColor(ak.inkSoft.opacity(0.55))
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .frame(width: 198)
    }

    private var version: String {
        let v = Self.appVersion
        let b = Self.appBuild
        return "版本 \(v) (\(b))"
    }
}

extension Sidebar {
    private static var repoPlist: [String: Any]? {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }
        return plist
    }

    /// 裸二进制跑快照时没有 Info.plist，回落到仓库里的 Info.plist，避免版本号显示成死值
    static var appVersion: String {
        if let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            return v
        }
        return repoPlist?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    /// build 号同理：裸二进制里读不到就回落，不然永远显示 (1)
    static var appBuild: String {
        if let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String {
            return b
        }
        return repoPlist?["CFBundleVersion"] as? String ?? "0"
    }
}

private struct SidebarItem: View {
    @Environment(\.ak) private var ak
    var page: AppState.Page
    var selected: Bool
    var badge: Int
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                Text(page.title)
                    .font(AKFont.sans(12.5, weight: selected ? .medium : .regular))
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(AKFont.sans(10, weight: .medium))
                        .foregroundColor(ak.bg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(ak.accent))
                }
            }
            .foregroundColor(selected ? ak.accent : ak.inkSoft)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? ak.surface : (hovered ? ak.surface.opacity(0.6) : Color.clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(selected ? ak.border : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - 通用块

private struct PageHeader: View {
    @Environment(\.ak) private var ak
    var kicker: String
    var title: String
    var lede: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AKMeta(text: kicker)
            Text(title)
                .font(AKFont.serif(34))
                .foregroundColor(ak.ink)
            Text(lede)
                .font(AKFont.sans(13))
                .foregroundColor(ak.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SearchBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(ak.inkSoft.opacity(0.7))
            TextField("搜索工具", text: $state.query)
                .textFieldStyle(.plain)
                .font(AKFont.sans(12.5))
                .foregroundColor(ak.ink)
            if !state.query.isEmpty {
                Button {
                    state.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(ak.inkSoft.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ak.surface)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ak.border, lineWidth: 0.5))
        )
        .frame(width: 240)
    }
}

// MARK: - 工具页

private struct ToolsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    PageHeader(kicker: "A-KIT · TOOLS",
                               title: "工具",
                               lede: "自己写的 macOS 工具都在这里。装、更、删，一处管完。")
                    Spacer()
                    SearchBar().padding(.top, 18)
                }
                .padding(.bottom, 22)

                HStack(spacing: 18) {
                    StatChip(label: "已安装", value: "\(state.installedCount)")
                    StatChip(label: "可更新", value: "\(state.updates.count)", accent: state.updates.count > 0)
                    StatChip(label: "菜单栏在线", value: "\(state.connected.count)")
                    if !state.imported.isEmpty {
                        StatChip(label: "来自链接", value: "\(state.imported.count)")
                    }
                    Spacer()
                    Button("从链接安装") {
                        state.importCandidate = nil
                        state.importError = nil
                        state.showImportSheet = true
                    }
                    .buttonStyle(AKPrimaryButtonStyle(filled: false))
                    Button("重新扫描") { Task { await state.refreshAll() } }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                }
                .padding(.bottom, 8)

                if state.filtered.isEmpty {
                    EmptyState(text: state.query.isEmpty ? "还没有登记任何工具" : "没有匹配「\(state.query)」的工具",
                               hint: state.query.isEmpty ? "A-Kit 本身不带工具。点右上角「从链接安装」粘一个工具的 GitHub 地址；本机已有的源码工具写进 tools.local.json（akit local 看路径）" : "")
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        AKHairline()
                        ForEach(state.filtered) { entry in
                            ToolRowView(entry: entry)
                            AKHairline()
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
        .sheet(isPresented: Binding(get: { state.selectedId != nil }, set: { if !$0 { state.selectedId = nil } })) {
            if let id = state.selectedId, let entry = state.entry(id) {
                ToolDetailSheet(entry: entry)
                    .environmentObject(state)
            }
        }
    }
}

private struct StatChip: View {
    @Environment(\.ak) private var ak
    var label: String
    var value: String
    var accent = false

    var body: some View {
        HStack(spacing: 5) {
            Text(value)
                .font(AKFont.serif(15))
                .foregroundColor(accent ? ak.accent2 : ak.ink)
            Text(label)
                .font(AKFont.sans(11))
                .foregroundColor(ak.inkSoft)
        }
    }
}

private struct EmptyState: View {
    @Environment(\.ak) private var ak
    var text: String
    var hint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(AKFont.serif(17))
                .foregroundColor(ak.inkSoft)
            if !hint.isEmpty {
                Text(hint)
                    .font(AKFont.sans(12))
                    .foregroundColor(ak.inkSoft.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 工具行

private struct ToolRowView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    var entry: ToolEntry
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 26) {
            VStack(alignment: .leading, spacing: 5) {
                AKMeta(text: entry.isInstalled ? "已安装" : "未安装",
                       color: entry.isInstalled ? ak.accent : ak.inkSoft.opacity(0.7))
                Text(entry.installed?.displayVersion ?? (entry.latest?.version ?? "—"))
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft)
                if let d = entry.installed?.modified {
                    Text(Self.day.string(from: d))
                        .font(AKFont.sans(10.5))
                        .foregroundColor(ak.inkSoft.opacity(0.65))
                }
            }
            .frame(width: 96, alignment: .leading)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(entry.name)
                    .font(AKFont.serif(19))
                    .foregroundColor(hovered ? ak.accent : ak.ink)
                if !entry.tagline.isEmpty {
                    Text(entry.tagline)
                        .font(AKFont.sans(12.5))
                        .foregroundColor(ak.inkSoft)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 5) {
                    if state.isConnected(entry) {
                        AKTag(text: "菜单栏在线", tint: ak.accent)
                    }
                    if entry.updateAvailable, let v = entry.latest?.version {
                        AKTag(text: "可更新到 \(v)", tint: ak.accent2)
                    }
                    if let s = state.statusText(entry) {
                        AKTag(text: s)
                    }
                    if state.isImported(entry) {
                        AKTag(text: "链接安装", tint: ak.accent2)
                    }
                    if let size = state.sizes[entry.id], size > 0 {
                        AKTag(text: Self.mb(size))
                    }
                    if entry.spec == nil {
                        AKTag(text: "未登记")
                    }
                    if !entry.isInstalled, entry.latest?.url == nil, entry.spec != nil {
                        AKTag(text: entry.spec?.source != nil ? "可源码重建" : "暂无下载源", tint: ak.accent2.opacity(0.85))
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if entry.isInstalled {
                    Button("打开") { state.open(entry) }
                        .buttonStyle(AKPrimaryButtonStyle())
                } else if entry.latest?.url != nil {
                    Button("安装") { state.install(entry, isUpdate: false) }
                        .buttonStyle(AKPrimaryButtonStyle())
                } else if entry.spec?.source != nil {
                    Button("重建安装") { state.rebuild(entry) }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                }
                if entry.updateAvailable {
                    Button("更新") { state.install(entry, isUpdate: true) }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                }
                Menu {
                    Button("详情") { state.selectedId = entry.id }
                    if entry.isInstalled {
                        Button("在访达中显示") { state.reveal(entry) }
                        Button("体检") { state.runHealth(entry); state.selectedId = entry.id }
                        Divider()
                        Button("卸载…") {
                            state.selectedId = entry.id
                        }
                    }
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
        .onTapGesture { state.selectedId = entry.id }
    }

    static let day: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func mb(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(bytes) / 1024)
    }
}

// MARK: - 更新页

private struct UpdatesPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    PageHeader(kicker: "A-KIT · UPDATES",
                               title: "更新",
                               lede: "跟 GitHub Releases 上的版本比对，只列真的能更的。")
                    Spacer()
                    VStack(alignment: .trailing, spacing: 8) {
                        Button("检查更新") { Task { await state.checkUpdates(silent: false) } }
                            .buttonStyle(AKPrimaryButtonStyle())
                        Button("全部体检") { state.runHealthAll() }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false))
                    }
                    .padding(.top, 18)
                }
                .padding(.bottom, 22)

                if state.updates.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("都是最新的")
                            .font(AKFont.serif(20))
                            .foregroundColor(ak.ink)
                        Text(state.lastRefresh.map { "上次检查 \(Self.time.string(from: $0))" } ?? "还没检查过")
                            .font(AKFont.sans(12))
                            .foregroundColor(ak.inkSoft)
                    }
                    .padding(.top, 26)
                } else {
                    VStack(spacing: 0) {
                        AKHairline()
                        ForEach(state.updates) { entry in
                            HStack(alignment: .top, spacing: 20) {
                                AKMeta(text: entry.latest?.releasedAt ?? "—").frame(width: 96, alignment: .leading)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name).font(AKFont.serif(18)).foregroundColor(ak.ink)
                                    Text("\(entry.installed?.version ?? "—") → \(entry.latest?.version ?? "—")")
                                        .font(AKFont.sans(12))
                                        .foregroundColor(ak.accent2)
                                    if let notes = entry.latest?.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(AKFont.sans(12))
                                            .foregroundColor(ak.inkSoft)
                                            .lineLimit(3)
                                    }
                                }
                                Spacer()
                                Button("更新") { state.install(entry, isUpdate: true) }
                                    .buttonStyle(AKPrimaryButtonStyle())
                            }
                            .padding(.vertical, 18)
                            AKHairline()
                        }
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

// MARK: - 菜单栏页

private struct MenuBarPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(kicker: "A-KIT · MENU BAR",
                           title: "菜单栏",
                           lede: "接入 A-Kit 的工具会把图标收进来，在这里决定谁显示、谁折叠、归到哪组。")
                    .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("单击图标")
                            .font(AKFont.sans(12.5))
                            .foregroundColor(ak.inkSoft)
                        Picker("", selection: Binding(
                            get: { state.layout.clickBehavior },
                            set: { v in state.layout.clickBehavior = v; state.layout.save(); state.objectWillChange.send() }
                        )) {
                            Text("打开面板").tag("panel")
                            Text("原生菜单").tag("menu")
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                        Spacer()
                        Text("全局快捷键 \(state.settings.hotkey)")
                            .font(AKFont.mono(11))
                            .foregroundColor(ak.inkSoft)
                    }
                    Text("没装或没运行 A-Kit 时，各工具照常显示自己的图标 —— 接管是可选的，不是必须的。")
                        .font(AKFont.sans(11.5))
                        .foregroundColor(ak.inkSoft.opacity(0.8))
                }
                .padding(.bottom, 18)

                VStack(spacing: 0) {
                    AKHairline()
                    ForEach(state.entries.filter { $0.isInstalled }) { entry in
                        HStack(spacing: 16) {
                            Toggle("", isOn: Binding(
                                get: { !state.layout.isHidden(entry.id) },
                                set: { _ in state.toggleHidden(entry) }
                            ))
                            .toggleStyle(.switch)
                            .tint(ak.accent)
                            .labelsHidden()
                            .scaleEffect(0.75)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                    .font(AKFont.sans(13, weight: .medium))
                                    .foregroundColor(ak.ink)
                                Text(state.isConnected(entry) ? "已接入 · 图标由 A-Kit 代管" : "未接入 · 使用自己的图标")
                                    .font(AKFont.sans(11))
                                    .foregroundColor(state.isConnected(entry) ? ak.accent : ak.inkSoft.opacity(0.75))
                            }

                            Spacer()

                            Menu {
                                ForEach(state.layout.groups) { g in
                                    Button(g.title) { state.move(entry, to: g.id) }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(state.layout.groups.first(where: { $0.items.contains(entry.id) })?.title ?? "未分组")
                                        .font(AKFont.sans(11))
                                        .foregroundColor(ak.inkSoft)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 7, weight: .medium))
                                        .foregroundColor(ak.inkSoft.opacity(0.7))
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 6).fill(ak.bg))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(ak.border, lineWidth: 0.5))
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                        }
                        .padding(.vertical, 13)
                        AKHairline()
                    }
                }

                HStack(spacing: 10) {
                    Text("分组")
                        .font(AKFont.sans(12, weight: .medium))
                        .foregroundColor(ak.inkSoft)
                    ForEach(state.layout.groups) { g in
                        HStack(spacing: 4) {
                            Text(g.title).font(AKFont.sans(11.5)).foregroundColor(ak.ink)
                            if state.layout.groups.count > 1 {
                                Button {
                                    state.removeGroup(g.id)
                                } label: {
                                    Image(systemName: "xmark").font(.system(size: 8))
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(ak.inkSoft)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(ak.surface))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(ak.border, lineWidth: 0.5))
                    }
                    Button("+ 新建分组") {
                        state.addGroup("分组 \(state.layout.groups.count + 1)")
                    }
                    .buttonStyle(AKPrimaryButtonStyle(filled: false))
                }
                .padding(.top, 18)
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - 第三方页

private struct ThirdPartyPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(kicker: "A-KIT · OTHERS",
                           title: "第三方",
                           lede: "工具住在各自的仓库，A-Kit 只认链接；别人没接口的 app 只能引导，不承诺。")
                    .padding(.bottom, 22)

                // 接入引导
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("把你的工具接进来")
                            .font(AKFont.serif(17))
                            .foregroundColor(ak.ink)
                        Spacer()
                        AKTag(text: "3 步 · 约 20 行代码", tint: ak.accent)
                    }
                    Text("接进来之后：A-Kit 能替你渲染菜单栏菜单、显示实时状态、跟别的工具收发事件。没装 A-Kit 的用户完全不受影响 —— SDK 连不上 Hub 时就什么都不做。")
                        .font(AKFont.sans(12.5))
                        .foregroundColor(ak.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    step(1, "拿到 SDK", "单文件 AKitStatusKit.swift 直接拖进工程，或者加 SwiftPM 依赖（零第三方依赖，只 import Foundation）。")
                    CopyBlock(title: "SwiftPM", code: """
                    .package(url: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS.git", from: "0.3.0")
                    """)

                    step(2, "启动时报到", "把菜单项描述给 Hub，Hub 一连上就会要求你把图标收起来。")
                    CopyBlock(title: "AppDelegate / 启动处", code: Self.snippet)

                    step(3, "让 A-Kit 认识你的 Release", "仓库根目录放一个 akit.json，别人就能用「从链接安装」直接装你。")
                    CopyBlock(title: "akit.json", code: Self.manifestSnippet)

                    HStack(spacing: 10) {
                        Button("接入文档（API）") {
                            if let url = URL(string: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS/blob/main/docs/SDK.md") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Button("工具仓库规范") {
                            if let url = URL(string: "https://github.com/BacheLor11/A-Kit-Tools-Hub-macOS/blob/main/docs/TOOL-REPO.md") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Button("复制 akit.json") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.manifestSnippet, forType: .string)
                            state.showToast("已复制 akit.json 模板", ok: true)
                        }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Spacer()
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 10).fill(ak.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ak.border, lineWidth: 0.5))
                .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 12) {
                    Text("为什么别人的 app 不能真接管")
                        .font(AKFont.serif(17))
                        .foregroundColor(ak.ink)
                    Text("macOS 没有公开 API 让一个 app 读取、移动或隐藏另一个 app 的菜单栏图标。Bartender、Ice 这类工具依靠「辅助功能」权限模拟点击、或把图标推到屏幕外，macOS 26 起系统还会自己接管可见性，所以经常失灵。")
                        .font(AKFont.sans(12.5))
                        .foregroundColor(ak.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A-Kit 不这么做：不申请辅助功能、不注入别人的进程。自家工具走协议，第三方只给建议。")
                        .font(AKFont.sans(12.5))
                        .foregroundColor(ak.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 10).fill(ak.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ak.border, lineWidth: 0.5))
                .padding(.bottom, 22)

                VStack(alignment: .leading, spacing: 10) {
                    Text("手动收起来")
                        .font(AKFont.serif(17))
                        .foregroundColor(ak.ink)
                    Label("按住 ⌘ 拖动菜单栏图标，可以把它移出菜单栏（macOS 自带）", systemImage: "1.circle")
                    Label("系统设置 → 菜单栏，可以单独关闭系统项目的显示", systemImage: "2.circle")
                    Label("如果你自己的工具接入了 A-Kit，它的图标会自动收进 A-Kit，无需手动处理", systemImage: "3.circle")
                }
                .font(AKFont.sans(12.5))
                .foregroundColor(ak.inkSoft)

                Spacer(minLength: 20)
                Text("已接入 A-Kit 的工具：\(state.connected.isEmpty ? "暂无" : state.connected.values.map(\.name).joined(separator: "、"))")
                    .font(AKFont.sans(12))
                    .foregroundColor(ak.inkSoft)
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)")
                .font(AKFont.serif(11))
                .foregroundColor(ak.bg)
                .frame(width: 18, height: 18)
                .background(Circle().fill(ak.ink))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(AKFont.sans(12.5, weight: .medium)).foregroundColor(ak.ink)
                Text(detail).font(AKFont.sans(11.5)).foregroundColor(ak.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static let snippet = """
    import AKitStatusKit

    // 连上就收起自己的图标，断开就还回来
    AKHubClient.shared.onConnectionChange = { connected in
        statusItem.isVisible = !connected
    }

    AKHubClient.shared.onInvoke = { itemId in
        switch itemId {
        case "toggle": toggle()
        case "settings": openSettings()
        default: break
        }
    }

    AKHubClient.shared.start(info: AKToolInfo(
        bundleId: Bundle.main.bundleIdentifier ?? "",
        name: "MyTool",
        version: "1.0.0",
        status: "空闲",
        menu: [
            AKMenuItem(id: "toggle", title: "开始", kind: .toggle, checked: false),
            AKMenuItem(id: "settings", title: "设置…"),
        ]))
    """

    static let manifestSnippet = """
    {
      "schemaVersion": 1,
      "id": "mytool",
      "name": "MyTool",
      "tagline": "一句话说明它干什么",
      "bundleId": "com.example.MyTool",
      "asset": "MyTool-*.zip",
      "statusBar": { "supported": true },
      "minOS": "13.0"
    }
    """
}

// MARK: - 代码块

private struct CopyBlock: View {
    @Environment(\.ak) private var ak
    var title: String
    var code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(AKFont.sans(10.5, weight: .medium))
                    .foregroundColor(ak.inkSoft.opacity(0.8))
                Spacer()
                Button(copied ? "已复制" : "复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        copied = false
                    }
                }
                .buttonStyle(.plain)
                .font(AKFont.sans(10.5))
                .foregroundColor(ak.accent)
            }
            Text(display)
                .font(AKFont.mono(10.5))
                .foregroundColor(ak.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ak.bg))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(ak.border, lineWidth: 0.5))
        }
    }

    /// 页面里只露前 14 行，复制的是完整内容
    private var display: String {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 10 else { return code }
        return lines.prefix(10).joined(separator: "\n") + "\n…（复制得到完整内容）"
    }
}

// MARK: - 设置页

private struct SettingsPage: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(kicker: "A-KIT · SETTINGS", title: "设置", lede: "清单从哪来、装到哪、留几份备份。")

                section("清单") {
                    SettingField(label: "Manifest 地址", value: state.settings.manifestURL) { v in
                        state.updateSettings { $0.manifestURL = v }
                        Task { await state.loadManifest(); await state.rescan() }
                    }
                    hint("当前：\(state.manifestLabel)")
                }

                section("安装") {
                    SettingField(label: "安装目录", value: state.settings.installDirectory) { v in
                        state.updateSettings { $0.installDirectory = v }
                    }
                    SettingField(label: "扫描目录（逗号分隔）", value: state.settings.scanDirectories.joined(separator: ", ")) { v in
                        state.updateSettings { $0.scanDirectories = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        Task { await state.rescan() }
                    }
                    SettingField(label: "自动发现的 bundle 前缀", value: state.settings.bundlePrefixes.joined(separator: ", ")) { v in
                        state.updateSettings { $0.bundlePrefixes = v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
                        Task { await state.rescan() }
                    }
                    HStack {
                        Text("保留备份").font(AKFont.sans(12.5)).foregroundColor(ak.inkSoft)
                        Stepper("\(state.settings.keepBackups) 份",
                                value: Binding(get: { state.settings.keepBackups },
                                               set: { v in state.updateSettings { $0.keepBackups = v } }),
                                in: 0...10)
                        .font(AKFont.sans(12))
                        Spacer()
                    }
                }

                section("GitHub 安装") {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("访问令牌")
                            .font(AKFont.sans(12))
                            .foregroundColor(ak.inkSoft)
                            .frame(width: 168, alignment: .leading)
                        SecureField("可选：ghp_… / github_pat_…", text: Binding(
                            get: { state.settings.githubToken },
                            set: { v in state.updateSettings { $0.githubToken = v } }))
                            .textFieldStyle(.plain)
                            .font(AKFont.mono(11.5))
                            .foregroundColor(ak.ink)
                        Spacer(minLength: 0)
                    }
                    hint("不填也能用，但未登录的 GitHub API 每个 IP 每小时只有 60 次，很容易被限流。只读权限就够，不用勾任何写权限。")
                    HStack(spacing: 10) {
                        Button("检查来源更新") {
                            Task { await state.checkGitHubUpdates(silent: false) }
                        }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Button("管理已装来源") {
                            state.cancelImport()
                            state.showImportSheet = true
                        }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Spacer()
                    }
                    hint(state.lastImportCheck.map { "上次检查：\(Self.time.string(from: $0))" } ?? "还没检查过")
                }

                section("行为") {
                    toggleRow("启动时检查更新", isOn: state.settings.autoCheckUpdates) { v in
                        state.updateSettings { $0.autoCheckUpdates = v }
                    }
                    toggleRow("显示菜单栏图标", isOn: state.settings.showMenuBarIcon) { v in
                        state.updateSettings { $0.showMenuBarIcon = v }
                        NotificationCenter.default.post(name: .akitMenuBarVisibilityChanged, object: nil)
                    }
                    toggleRow("在 Dock 显示", isOn: state.settings.showDockIcon) { v in
                        state.updateSettings { $0.showDockIcon = v }
                        NotificationCenter.default.post(name: .akitDockVisibilityChanged, object: nil)
                    }
                    SettingField(label: "全局快捷键", value: state.settings.hotkey) { v in
                        state.updateSettings { $0.hotkey = v }
                    }
                    hint("改快捷键后需要重启 A-Kit 生效")
                }

                section("开发者") {
                    toggleRow("源码改动后自动重建（热重载）", isOn: state.settings.devAutoRebuild) { v in
                        state.updateSettings { $0.devAutoRebuild = v }
                    }
                    hint(state.devWatchActive
                         ? "正在盯着 \(state.watching.count) 个源码目录，改文件后约 2 秒触发重建"
                         : "只在清单里配了 source 的工具上生效；打开后改完代码不用手动点「重建」")
                    if !state.watching.isEmpty {
                        Text(state.watching.joined(separator: " · "))
                            .font(AKFont.mono(10.5))
                            .foregroundColor(ak.inkSoft.opacity(0.7))
                    }
                }

                section("配置") {
                    HStack(spacing: 10) {
                        Button("导出配置") { state.exportConfig() }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Button("导入配置") { state.importConfig() }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Button("打开数据目录") {
                            NSWorkspace.shared.open(AKPaths.support)
                        }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        Spacer()
                    }
                    hint("导出内容：清单地址、安装目录、菜单栏布局、工具列表。换 Mac 时直接搬。")
                }

                section("关于") {
                    Text("A-Kit · 自己写的小工具，自己收着。")
                        .font(AKFont.sans(12.5)).foregroundColor(ak.inkSoft)
                    Text("日志：\(AKPaths.logs.appendingPathComponent("akit.log").path)")
                        .font(AKFont.mono(10.5)).foregroundColor(ak.inkSoft.opacity(0.7))
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 30)
            .padding(.bottom, 40)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            AKMeta(text: title)
            VStack(alignment: .leading, spacing: 10) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(ak.surface))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(ak.border, lineWidth: 0.5))
        }
    }

    private func toggleRow(_ label: String, isOn: Bool, onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(label).font(AKFont.sans(12.5)).foregroundColor(ak.inkSoft)
            Spacer()
            Toggle("", isOn: Binding(get: { isOn }, set: { onChange($0) }))
                .toggleStyle(.switch)
                .tint(ak.accent)
                .labelsHidden()
                .scaleEffect(0.75)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text)
            .font(AKFont.sans(11))
            .foregroundColor(ak.inkSoft.opacity(0.7))
    }

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f
    }()
}

private struct SettingField: View {
    @Environment(\.ak) private var ak
    var label: String
    var value: String
    var onCommit: (String) -> Void
    @State private var text: String = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(AKFont.sans(12))
                .foregroundColor(ak.inkSoft)
                .frame(width: 168, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(AKFont.mono(11.5))
                .foregroundColor(ak.ink)
                .onSubmit { onCommit(text) }
            Spacer(minLength: 0)
        }
        .onAppear { text = value }
        .onChange(of: value) { newValue in text = newValue }
    }
}

// MARK: - 详情

private struct ToolDetailSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    var entry: ToolEntry
    @State private var confirmUninstall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    AKMeta(text: entry.isInstalled ? "已安装 · \(entry.installed?.displayVersion ?? "")" : "未安装")
                    Spacer()
                    Button("关闭") { state.selectedId = nil }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                }
                .padding(.bottom, 14)

                Text(entry.name)
                    .font(AKFont.serif(30))
                    .foregroundColor(ak.ink)
                if !entry.tagline.isEmpty {
                    Text(entry.tagline)
                        .font(AKFont.sans(13))
                        .foregroundColor(ak.inkSoft)
                        .padding(.top, 4)
                }

                HStack(spacing: 10) {
                    if entry.isInstalled {
                        Button("打开") { state.open(entry) }
                            .buttonStyle(AKPrimaryButtonStyle())
                        Button("在访达中显示") { state.reveal(entry) }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false))
                    } else if entry.latest?.url != nil {
                        Button("安装") { state.install(entry, isUpdate: false) }
                            .buttonStyle(AKPrimaryButtonStyle())
                    }
                    if entry.updateAvailable {
                        Button("更新到 \(entry.latest?.version ?? "")") { state.install(entry, isUpdate: true) }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false))
                    }
                    if entry.spec?.source != nil {
                        Button("从源码重建") { state.rebuild(entry) }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false))
                    }
                    if entry.isInstalled {
                        Button("卸载") { confirmUninstall = true }
                            .buttonStyle(AKPrimaryButtonStyle(filled: false, danger: true))
                    }
                }
                .padding(.top, 16)

                if let h = state.health[entry.id] {
                    healthBlock(h)
                } else if entry.isInstalled {
                    Button("体检这个工具") { state.runHealth(entry) }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        .padding(.top, 16)
                }

                if let rec = state.usage.records[entry.id] {
                    AKHairline().padding(.top, 22)
                    AKMeta(text: "使用").padding(.top, 14)
                    HStack(spacing: 22) {
                        usageStat("打开过", "\(rec.openCount) 次")
                        if let d = rec.lastOpened {
                            usageStat("最近", Self.shortDate.string(from: d))
                        }
                        if let days = state.usage.daysSinceOpened(entry.id), days > 90 {
                            Text("\(days) 天没开过了，可以考虑卸载")
                                .font(AKFont.sans(11.5))
                                .foregroundColor(ak.accent2)
                        }
                    }
                    .padding(.top, 6)
                }

                if let notes = entry.latest?.notes, !notes.isEmpty {
                    AKHairline().padding(.top, 22)
                    Text("更新日志")
                        .font(AKFont.serif(17))
                        .foregroundColor(ak.ink)
                        .padding(.top, 16)
                    Text(notes)
                        .font(AKFont.sans(12.5))
                        .foregroundColor(ak.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }

                if let imp = state.imported.first(where: { $0.id == entry.id }) {
                    AKHairline().padding(.top, 22)
                    AKMeta(text: "来源").padding(.top, 14)
                    VStack(alignment: .leading, spacing: 5) {
                        if let slug = imp.slug, let url = URL(string: "https://github.com/\(slug)") {
                            Link(slug, destination: url)
                                .font(AKFont.sans(12.5))
                                .foregroundColor(ak.accent)
                        } else {
                            Text("直链安装")
                                .font(AKFont.sans(12.5))
                                .foregroundColor(ak.inkSoft)
                        }
                        Text("\(imp.tag.isEmpty ? imp.version : imp.tag) · \(imp.assetName)")
                            .font(AKFont.mono(10.5))
                            .foregroundColor(ak.inkSoft)
                        Text("记于 \(String(imp.addedAt.prefix(10)))")
                            .font(AKFont.sans(10.5))
                            .foregroundColor(ak.inkSoft.opacity(0.65))
                    }
                    .padding(.top, 8)
                    Button("忘掉这个来源（不删 app）") { state.forgetSource(entry) }
                        .buttonStyle(AKPrimaryButtonStyle(filled: false))
                        .padding(.top, 6)
                }

                if let article = entry.spec?.article, let url = URL(string: article) {
                    AKHairline().padding(.top, 22)
                    Link(destination: url) {
                        Text("在博客读这篇 →")
                            .font(AKFont.sans(12.5))
                            .foregroundColor(ak.accent)
                    }
                    .padding(.top, 14)
                }

                if let path = entry.installed?.path {
                    Text(path.path)
                        .font(AKFont.mono(10))
                        .foregroundColor(ak.inkSoft.opacity(0.6))
                        .padding(.top, 18)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 620, height: 560)
        .background(ak.bg)
        .confirmationDialog("卸载 \(entry.name)？", isPresented: $confirmUninstall) {
            Button("移到废纸篓", role: .destructive) { state.uninstall(entry, alsoSupportFiles: false) }
            Button("连同配置文件一起删除", role: .destructive) { state.uninstall(entry, alsoSupportFiles: true) }
            Button("取消", role: .cancel) { }
        } message: {
            Text("app 会被移到废纸篓，不会直接删除。")
        }
    }

    private func usageStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AKFont.sans(10.5))
                .foregroundColor(ak.inkSoft.opacity(0.75))
            Text(value)
                .font(AKFont.sans(12))
                .foregroundColor(ak.ink)
        }
    }

    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private func healthBlock(_ h: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            AKMeta(text: "体检", color: h.passed ? ak.accent : ak.accent2)
            row("签名", h.signer)
            row("Hardened Runtime", h.hardened ? "已开启" : "关闭")
            row("Gatekeeper", h.gatekeeper + (h.notarized ? " · 已公证" : ""))
            row("架构", h.architectures.isEmpty ? "—" : h.architectures.joined(separator: " / "))
            row("最低系统", h.minOS)
            if h.quarantined { row("隔离属性", "带 quarantine（首次打开会被拦）") }
            ForEach(h.warnings, id: \.self) { w in
                Text("· \(w)")
                    .font(AKFont.sans(11.5))
                    .foregroundColor(ak.accent2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9).fill(ak.surface))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(ak.border, lineWidth: 0.5))
        .padding(.top, 18)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k).font(AKFont.sans(11.5)).foregroundColor(ak.inkSoft).frame(width: 120, alignment: .leading)
            Text(v).font(AKFont.sans(11.5)).foregroundColor(ak.ink)
            Spacer()
        }
    }
}

// MARK: - Toast

private struct ToastOverlay: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        Group {
            if let t = state.toast {
                HStack(spacing: 7) {
                    Image(systemName: t.ok ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.system(size: 11))
                    Text(t.text).font(AKFont.sans(12))
                }
                .foregroundColor(ak.bg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(t.ok ? ak.ink : ak.accent2))
                .padding(.bottom, 22)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: state.toast)
    }
}

// MARK: - 任务浮层

struct JobBar: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak

    var body: some View {
        if let job = state.job {
            HStack(spacing: 10) {
                ProgressView().scaleEffect(0.55).frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(job.title).font(AKFont.sans(11.5, weight: .medium)).foregroundColor(ak.ink)
                    Text(job.detail).font(AKFont.sans(10.5)).foregroundColor(ak.inkSoft).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(ak.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ak.border, lineWidth: 0.5))
        }
    }
}

extension Notification.Name {
    static let akitMenuBarVisibilityChanged = Notification.Name("akit.menubar.visibility")
    static let akitDockVisibilityChanged = Notification.Name("akit.dock.visibility")
}
