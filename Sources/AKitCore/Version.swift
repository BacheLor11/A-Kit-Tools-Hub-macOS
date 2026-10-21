import Foundation

/// 版本号比较：支持 1.2.3 / 1.2.3-beta.1 / 1.2.3 (42) 这类常见写法。
/// 规则：先比数字段，数字段相同再按预发布标签（release > beta > alpha），最后比 build。
public struct AKVersion: Comparable, CustomStringConvertible, Hashable {
    public let raw: String
    private let numbers: [Int]
    private let prerelease: String?
    private let build: Int

    public init(_ raw: String, build: Int = 0) {
        self.raw = raw.trimmingCharacters(in: .whitespaces)
        var core = self.raw
        var pre: String? = nil
        if let dash = core.firstIndex(where: { $0 == "-" || $0 == " " }) {
            let tail = String(core[core.index(after: dash)...])
            core = String(core[..<dash])
            pre = tail.isEmpty ? nil : tail
        }
        self.prerelease = pre
        self.numbers = core.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        self.build = build
    }

    public var description: String { raw }

    private var prereleaseRank: Int {
        guard let p = prerelease?.lowercased() else { return 3 }
        if p.contains("alpha") { return 0 }
        if p.contains("beta") { return 1 }
        if p.contains("rc") { return 2 }
        return 2
    }

    public static func < (lhs: AKVersion, rhs: AKVersion) -> Bool {
        let n = max(lhs.numbers.count, rhs.numbers.count)
        for i in 0..<n {
            let a = i < lhs.numbers.count ? lhs.numbers[i] : 0
            let b = i < rhs.numbers.count ? rhs.numbers[i] : 0
            if a != b { return a < b }
        }
        if lhs.prereleaseRank != rhs.prereleaseRank { return lhs.prereleaseRank < rhs.prereleaseRank }
        if lhs.build != rhs.build { return lhs.build < rhs.build }
        return false
    }

    public static func == (lhs: AKVersion, rhs: AKVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
