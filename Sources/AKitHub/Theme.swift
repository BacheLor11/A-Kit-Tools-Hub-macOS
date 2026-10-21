import SwiftUI
import AppKit

// MARK: - 颜色

extension NSColor {
    convenience init(srgbHex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((srgbHex >> 16) & 0xFF) / 255
        let g = CGFloat((srgbHex >> 8) & 0xFF) / 255
        let b = CGFloat(srgbHex & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}

/// 与博客 `global.css` 一一对应的设计令牌
struct AKScheme {
    var bg: Color
    var surface: Color
    var ink: Color
    var inkSoft: Color
    var accent: Color
    var accent2: Color
    var border: Color
    var shadow: Color

    static let light = AKScheme(
        bg: Color(nsColor: NSColor(srgbHex: 0xFBFAF7)),
        surface: Color.white,
        ink: Color(nsColor: NSColor(srgbHex: 0x1A1A1A)),
        inkSoft: Color(nsColor: NSColor(srgbHex: 0x5B574E)),
        accent: Color(nsColor: NSColor(srgbHex: 0x34557A)),
        accent2: Color(nsColor: NSColor(srgbHex: 0xB5562E)),
        border: Color(nsColor: NSColor(srgbHex: 0xE7E2D8)),
        shadow: Color.black.opacity(0.08)
    )

    static let dark = AKScheme(
        bg: Color(nsColor: NSColor(srgbHex: 0x15171A)),
        surface: Color(nsColor: NSColor(srgbHex: 0x202326)),
        ink: Color(nsColor: NSColor(srgbHex: 0xECE9E2)),
        inkSoft: Color(nsColor: NSColor(srgbHex: 0xA8A29A)),
        accent: Color(nsColor: NSColor(srgbHex: 0x7BA3CC)),
        accent2: Color(nsColor: NSColor(srgbHex: 0xD98A5E)),
        border: Color(nsColor: NSColor(srgbHex: 0x2E3236)),
        shadow: Color.black.opacity(0.45)
    )

    static func of(_ scheme: ColorScheme) -> AKScheme {
        scheme == .dark ? .dark : .light
    }
}

private struct AKSchemeKey: EnvironmentKey {
    static let defaultValue = AKScheme.light
}

extension EnvironmentValues {
    var ak: AKScheme {
        get { self[AKSchemeKey.self] }
        set { self[AKSchemeKey.self] = newValue }
    }
}

// MARK: - 字体

enum AKFont {
    static func serif(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom("Songti SC", size: size).weight(bold ? .bold : .regular)
    }
    static func sans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat) -> Font {
        .system(size: size, design: .monospaced)
    }
    /// 博客左上角那个手写体
    static var brand: Font { .custom("Zapfino", size: 15) }
}

// MARK: - 通用组件

struct AKPrimaryButtonStyle: ButtonStyle {
    @Environment(\.ak) private var ak
    var filled = true
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AKFont.sans(12.5, weight: .medium))
            .foregroundColor(filled ? ak.bg : (danger ? ak.accent2 : ak.accent))
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(filled ? (danger ? ak.accent2 : ak.ink) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(filled ? Color.clear : ak.border, lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(Rectangle())
    }
}

/// 小号全大写标签，对应博客 `.card .meta`
struct AKMeta: View {
    @Environment(\.ak) private var ak
    var text: String
    var color: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(AKFont.sans(10.5, weight: .medium))
            .tracking(0.8)
            .foregroundColor(color ?? ak.accent)
    }
}

struct AKHairline: View {
    @Environment(\.ak) private var ak
    var body: some View {
        Rectangle().fill(ak.border).frame(height: 1)
    }
}

struct AKTag: View {
    @Environment(\.ak) private var ak
    var text: String
    var tint: Color? = nil

    var body: some View {
        Text(text)
            .font(AKFont.sans(10.5, weight: .medium))
            .foregroundColor(tint ?? ak.inkSoft)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ak.bg)
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(ak.border, lineWidth: 0.5))
            )
    }
}

// MARK: - 窗口背景

enum AKWindowColor {
    static var dynamic: NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(srgbHex: dark ? 0x15171A : 0xFBFAF7)
        }
    }
}
