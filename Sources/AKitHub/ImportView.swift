import SwiftUI
import AppKit
import AKitCore

/// 「从链接安装」面板：粘贴 GitHub 地址 → 解析 → 预览 → 装
struct ImportSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.ak) private var ak
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            inputRow
            AKHairline()
            content
            AKHairline()
            footer
        }
        .frame(width: 640, height: 540)
        .background(ak.bg)
        .onAppear {
            if input.isEmpty, let c = state.importCandidate { input = c.input }
            focused = true
        }
    }

    // MARK: 头

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            AKMeta(text: "A-KIT · INSTALL FROM GITHUB")
            Text("从链接安装")
                .font(AKFont.serif(26))
                .foregroundColor(ak.ink)
            Text("贴一个 GitHub 仓库、某个 Release，或者 .zip / .dmg 直链。带 akit.json 的工具能被完整识别，没有也能装。")
                .font(AKFont.sans(12))
                .foregroundColor(ak.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 16)
    }

    // MARK: 输入

    private var inputRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(ak.inkSoft.opacity(0.7))
                TextField("https://github.com/owner/repo 或 owner/repo", text: $input)
                    .textFieldStyle(.plain)
                    .font(AKFont.mono(12))
                    .foregroundColor(ak.ink)
                    .focused($focused)
                    .onSubmit { state.inspectImport(input) }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ak.surface))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(ak.border, lineWidth: 0.8))

            Button(state.parsing ? "解析中…" : "解析") { state.inspectImport(input) }
                .buttonStyle(AKPrimaryButtonStyle())
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || state.parsing)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if state.parsing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在问 GitHub 要 Release 信息…")
                            .font(AKFont.sans(12)).foregroundColor(ak.inkSoft)
                    }
                    .padding(.top, 18)
                } else if let err = state.importError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("没解析出来", systemImage: "exclamationmark.triangle")
                            .font(AKFont.sans(12.5, weight: .medium))
                            .foregroundColor(ak.accent2)
                        Text(err)
                            .font(AKFont.sans(12))
                            .foregroundColor(ak.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 12)
                } else if let c = state.importCandidate {
                    candidateCard(c)
                } else {
                    hints
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 14) {
            hintRow("building.2", "仓库地址",
                    "https://github.com/owner/repo —— 自动取最新 Release 里的 macOS 产物")
            hintRow("tag", "指定版本",
                    "…/releases/tag/v1.2.0 —— 回退或试新版时用")
            hintRow("shippingbox", "直链",
                    "https://…/X.zip 或 X.dmg —— 不限于 GitHub，装完不会再检查更新")
            Divider().padding(.vertical, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text("给工具作者")
                    .font(AKFont.sans(11.5, weight: .medium))
                    .foregroundColor(ak.ink)
                Text("在仓库根目录放一个 akit.json（名字、bundle id、挑哪个产物），A-Kit 就能精确识别、校验并自动更新。规范见项目里的 docs/SDK.md。")
                    .font(AKFont.sans(11.5))
                    .foregroundColor(ak.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ak.surface.opacity(0.65)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(ak.border, lineWidth: 0.5))
        }
    }

    private func hintRow(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundColor(ak.accent)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AKFont.sans(12, weight: .medium)).foregroundColor(ak.ink)
                Text(detail).font(AKFont.sans(11.5)).foregroundColor(ak.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: 候选卡片

    private func candidateCard(_ c: ImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(c.name)
                    .font(AKFont.serif(20))
                    .foregroundColor(ak.ink)
                if !c.version.isEmpty {
                    Text(c.version)
                        .font(AKFont.mono(11.5))
                        .foregroundColor(ak.inkSoft)
                }
                Spacer()
                if c.hasAKitManifest {
                    AKTag(text: "已接入 A-Kit", tint: ak.accent)
                } else {
                    AKTag(text: "无自描述", tint: ak.inkSoft.opacity(0.8))
                }
                if c.isPrerelease { AKTag(text: "预发布", tint: ak.accent2) }
            }

            if !c.tagline.isEmpty {
                Text(c.tagline)
                    .font(AKFont.sans(12.5))
                    .foregroundColor(ak.inkSoft)
            }

            VStack(alignment: .leading, spacing: 6) {
                infoLine("来源", c.slug ?? "直链")
                infoLine("版本", c.tag.isEmpty ? (c.version.isEmpty ? "安装后读取" : c.version) : "\(c.tag) → \(c.version)")
                infoLine("产物", "\(c.assetName) · \(Self.size(c.assetSize))")
                infoLine("格式", c.installKind)
                if let bid = Optional(c.bundleId), !bid.isEmpty {
                    infoLine("Bundle ID", bid)
                }
                if let minOS = c.minOS { infoLine("最低系统", minOS) }
                if let at = c.publishedAt { infoLine("发布", String(at.prefix(10))) }
            }

            if c.needsSudo {
                warnBox("PKG 需要管理员密码，A-Kit 不代跑 sudo。这个包装不了，得手动装。", danger: true)
            }
            ForEach(c.warnings, id: \.self) { w in
                warnBox(w, danger: false)
            }

            if let notes = c.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("更新说明")
                        .font(AKFont.sans(11, weight: .medium))
                        .foregroundColor(ak.inkSoft)
                    Text(Self.trimNotes(notes))
                        .font(AKFont.sans(11.5))
                        .foregroundColor(ak.inkSoft)
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ak.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(ak.border, lineWidth: 0.6))
    }

    private func infoLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(AKFont.sans(11))
                .foregroundColor(ak.inkSoft.opacity(0.75))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(AKFont.mono(11))
                .foregroundColor(ak.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func warnBox(_ text: String, danger: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: danger ? "xmark.octagon" : "info.circle")
                .font(.system(size: 10))
                .foregroundColor(danger ? ak.accent2 : ak.inkSoft.opacity(0.7))
                .padding(.top, 1)
            Text(text)
                .font(AKFont.sans(11))
                .foregroundColor(danger ? ak.accent2 : ak.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if let t = state.imported.last {
                Text("已装 \(state.imported.count) 个来自链接的工具")
                    .font(AKFont.sans(11))
                    .foregroundColor(ak.inkSoft.opacity(0.75))
            }
            Spacer()
            Button("取消") {
                state.cancelImport()
                dismiss()
            }
            .buttonStyle(AKPrimaryButtonStyle(filled: false))

            Button("安装") { state.confirmImport() }
                .buttonStyle(AKPrimaryButtonStyle())
                .disabled(state.importCandidate == nil || state.job != nil)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
    }

    // MARK: 工具

    static func size(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "大小未知" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: bytes)
    }

    static func trimNotes(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .prefix(8)
            .joined(separator: "\n")
    }
}
