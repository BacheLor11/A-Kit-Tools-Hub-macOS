import Foundation
import AppKit
import AKitPluginKit

/// 插件的加载器：扫描目录、`dlopen`、校验 ABI、拿到描述符。
///
/// 只负责「把插件变成可用的对象」，不管布局、不管 UI。
/// 不标 `@MainActor`：`dlopen` 本身不要求主线程，由调用方保证。
public final class AKPluginLoader {

    public enum LoadError: LocalizedError {
        case notABundle(String)
        case noInfoPlist(String)
        case noExecutable(String)
        case dlopenFailed(String, String)
        case missingEntry(String)
        case wrongType
        case abiMismatch(found: Int32, expected: Int32)

        public var errorDescription: String? {
            switch self {
            case .notABundle(let p): return "不是一个插件包：\(p)"
            case .noInfoPlist(let p): return "缺少 Info.plist：\(p)"
            case .noExecutable(let p): return "找不到可执行文件：\(p)"
            case .dlopenFailed(let p, let e): return "加载失败：\(p)\n\(e)"
            case .missingEntry(let p): return "插件没有导出 \(AKPluginEntrySymbol)：\(p)"
            case .wrongType: return "插件返回的对象不是 AKPluginDescriptor"
            case .abiMismatch(let f, let e): return "插件 ABI 是 \(f)，宿主需要 \(e)（该插件需要更新）"
            }
        }
    }

    /// 加载成功的插件
    public struct Loaded {
        public let record: AKPluginRecord
        public let descriptor: AKPluginDescriptor
        /// dlopen 的句柄。**不要 close**：插件创建的 NSView 还活着，
        /// 卸载只能靠「标记禁用 + 下次启动不加载」，运行期不能真卸载。
        public let handle: UnsafeMutableRawPointer

        public init(record: AKPluginRecord, descriptor: AKPluginDescriptor, handle: UnsafeMutableRawPointer) {
            self.record = record
            self.descriptor = descriptor
            self.handle = handle
        }
    }

    public init() {}

    // MARK: 读取清单（不加载代码）

    /// 读一个 `.akitplugin` 包的静态信息。软链会自动解到真实路径。
    public func readRecord(at bundleURL: URL) throws -> AKPluginRecord {
        let resolved = bundleURL.resolvingSymlinksInPath()
        guard resolved.pathExtension == "akitplugin" || bundleURL.pathExtension == "akitplugin" else {
            throw LoadError.notABundle(bundleURL.path)
        }
        let infoURL = resolved.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { throw LoadError.noInfoPlist(resolved.path) }

        let execName = (plist["CFBundleExecutable"] as? String) ?? resolved.deletingPathExtension().lastPathComponent
        let execURL = resolved.appendingPathComponent("Contents/MacOS/\(execName)")
        guard FileManager.default.fileExists(atPath: execURL.path) else {
            throw LoadError.noExecutable(execURL.path)
        }

        let id = (plist["AKPluginIdentifier"] as? String)
            ?? (plist["CFBundleIdentifier"] as? String)
            ?? resolved.deletingPathExtension().lastPathComponent
        let name = (plist["AKPluginDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? id
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "0"
        let abi = Int32((plist["AKPluginABIVersion"] as? Int) ?? 1)

        // both 模式：插件住在 app 包里，往上找 .app 的根
        var appPath: String?
        var cursor = resolved
        for _ in 0..<6 {
            if cursor.pathExtension == "app" { appPath = cursor.path; break }
            let parent = cursor.deletingLastPathComponent()
            if parent.path == cursor.path { break }
            cursor = parent
        }

        return AKPluginRecord(
            id: id, displayName: name, version: version,
            bundlePath: resolved.path,
            executablePath: execURL.path,
            abiVersion: abi,
            appPath: appPath,
            signedTeamId: Self.teamId(of: resolved)
        )
    }

    // MARK: 加载

    /// `dlopen` 并实例化插件。`host` 会被原样传给插件入口。
    public func load(record: AKPluginRecord, host: AKPluginHost) throws -> Loaded {
        guard record.abiVersion == AKPluginABIVersion else {
            throw LoadError.abiMismatch(found: record.abiVersion, expected: AKPluginABIVersion)
        }
        guard let handle = dlopen(record.executablePath, RTLD_NOW | RTLD_LOCAL) else {
            throw LoadError.dlopenFailed(record.executablePath, String(cString: dlerror()))
        }
        guard let sym = dlsym(handle, AKPluginEntrySymbol) else {
            throw LoadError.missingEntry(record.executablePath)
        }

        typealias Entry = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
        let entry = unsafeBitCast(sym, to: Entry.self)
        let hostPtr = Unmanaged.passUnretained(host).toOpaque()
        guard let raw = entry(hostPtr) else { throw LoadError.wrongType }

        let object = Unmanaged<AnyObject>.fromOpaque(raw).takeRetainedValue()
        guard let descriptor = object as? AKPluginDescriptor else { throw LoadError.wrongType }

        // 运行时再核一次：Info.plist 可以写假的，插件自己报的才算数
        let live = descriptor.abiVersion
        guard live == AKPluginABIVersion else {
            throw LoadError.abiMismatch(found: live, expected: AKPluginABIVersion)
        }

        return Loaded(record: record, descriptor: descriptor, handle: handle)
    }

    // MARK: 签名

    /// 读代码签名里的 Team ID。没签名或 ad-hoc 时返回 nil。
    static func teamId(of url: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dv", "--verbose=4", url.appendingPathComponent("Contents/MacOS").path]
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = pipe
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
            let v = line.replacingOccurrences(of: "TeamIdentifier=", with: "").trimmingCharacters(in: .whitespaces)
            return (v == "not set" || v.isEmpty) ? nil : v
        }
        return nil
    }
}
