import AppKit
import Foundation
import CryptoKit

public enum InstallerError: LocalizedError {
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case unzipFailed(String)
    case noAppInArchive
    case installFailed(String)
    case bundleIdMismatch(expected: String, actual: String)
    case buildFailed(String)

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let s): return "下载失败：\(s)"
        case .checksumMismatch(let e, let a): return "校验和不匹配（期望 \(e.prefix(12))… 实际 \(a.prefix(12))…）"
        case .unzipFailed(let s): return "解压失败：\(s)"
        case .noAppInArchive: return "压缩包里没找到 .app"
        case .installFailed(let s): return "安装失败：\(s)"
        case .bundleIdMismatch(let e, let a): return "包不匹配：清单是 \(e)，包里是 \(a)"
        case .buildFailed(let s): return "构建失败：\(s)"
        }
    }
}

/// 下载进度。`total <= 0` 表示服务器没给 Content-Length，只能显示「已下载多少」。
public struct DownloadProgress: Sendable {
    public var received: Int64
    public var total: Int64
    /// 字节/秒（0.25 秒滑动窗口算的，没开始算的时候是 0）
    public var speed: Double

    public init(received: Int64 = 0, total: Int64 = 0, speed: Double = 0) {
        self.received = received
        self.total = total
        self.speed = speed
    }

    /// 0…1。拿不到总长度时是 nil —— 那种情况界面要显示成不确定态，不能假装 0%。
    public var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, max(0, Double(received) / Double(total)))
    }

    /// 「12.3 MB / 45.6 MB · 3.1 MB/s」
    public var text: String {
        func size(_ n: Int64) -> String {
            let mb = Double(n) / 1_048_576
            return mb >= 1 ? String(format: "%.1f MB", mb) : String(format: "%.0f KB", Double(n) / 1024)
        }
        var s = total > 0 ? "\(size(received)) / \(size(total))" : size(received)
        if speed > 1 {
            s += String(format: " · %.1f MB/s", speed / 1_048_576)
        }
        return s
    }
}

/// URLSession 的下载进度回调只能走 delegate，这里把它包成 async/await。
///
/// 以前用 `URLSession.shared.download(from:)`：没有回调、没有进度，
/// 点完「更新」界面一动不动，用户以为按钮没生效。
private final class DownloadRunner: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let destination: URL
    private let onProgress: ((DownloadProgress) -> Void)?
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var finished = false
    private var lastSample = Date()
    private var lastBytes: Int64 = 0
    private var speed: Double = 0
    private var lastEmit = Date.distantPast

    init(destination: URL, onProgress: ((DownloadProgress) -> Void)?) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func run(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<URL, Error>) in
            continuation = c
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 60 * 30
            let s = URLSession(configuration: config, delegate: self, delegateQueue: nil)
            session = s
            s.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        session = nil
        let c = continuation
        continuation = nil
        switch result {
        case .success(let url): c?.resume(returning: url)
        case .failure(let e): c?.resume(throwing: e)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let now = Date()
        let dt = now.timeIntervalSince(lastSample)
        if dt >= 0.25 {
            speed = Double(totalBytesWritten - lastBytes) / dt
            lastSample = now
            lastBytes = totalBytesWritten
        }
        // 进度刷太密会把主线程塞满，10 fps 对进度条完全够
        guard now.timeIntervalSince(lastEmit) >= 0.1 else { return }
        lastEmit = now
        onProgress?(DownloadProgress(received: totalBytesWritten,
                                     total: max(totalBytesExpectedToWrite, 0),
                                     speed: speed))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode >= 400 {
            finish(.failure(InstallerError.downloadFailed("HTTP \(http.statusCode)")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(InstallerError.downloadFailed(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        finish(.failure(InstallerError.downloadFailed(error.localizedDescription)))
    }
}

public enum Installer {

    // MARK: 下载

    /// 带进度的下载。
    ///
    /// `onProgress` 在后台队列里回调（0.1 秒最多一次），调用方要自己切回主线程。
    public static func download(from url: URL, to dest: URL,
                                onProgress: ((DownloadProgress) -> Void)? = nil) async throws -> URL {
        AKPaths.ensure()
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let runner = DownloadRunner(destination: dest, onProgress: onProgress)
            let out = try await runner.run(url)
            onProgress?(DownloadProgress(received: fileSize(out), total: fileSize(out), speed: 0))
            AKLogInfo("install", "downloaded \(url.lastPathComponent) -> \(out.path)")
            return out
        } catch let e as InstallerError {
            throw e
        } catch {
            throw InstallerError.downloadFailed(error.localizedDescription)
        }
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(v?.fileSize ?? 0)
    }

    public static func sha256(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 解包

    public static func unzip(_ archive: URL, into dir: URL) throws -> URL {
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (code, out) = Shell.run("/usr/bin/ditto", ["-x", "-k", archive.path, dir.path])
        guard code == 0 else { throw InstallerError.unzipFailed(out) }
        guard let app = appInside(dir) else { throw InstallerError.noAppInArchive }
        return app
    }

    public static func appInside(_ dir: URL) -> URL? {
        let fm = FileManager.default
        if dir.pathExtension == "app" { return dir }
        if let kids = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            if let direct = kids.first(where: { $0.pathExtension == "app" }) { return direct }
        }
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let f as URL in e where f.pathExtension == "app" { return f }
        return nil
    }

    // MARK: 安装 / 覆盖

    @discardableResult
    public static func install(_ sourceApp: URL, into dir: URL, backupTo: URL? = nil,
                               expectedBundleId: String? = nil) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        if let expected = expectedBundleId,
           let bundle = Bundle(url: sourceApp),
           let actual = bundle.bundleIdentifier,
           actual != expected {
            throw InstallerError.bundleIdMismatch(expected: expected, actual: actual)
        }

        let dest = dir.appendingPathComponent(sourceApp.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            if let backupTo { try backup(dest, to: backupTo) }
            try FileManager.default.removeItem(at: dest)
        }
        let (code, out) = Shell.run("/usr/bin/ditto", [sourceApp.path, dest.path])
        guard code == 0 else { throw InstallerError.installFailed(out) }
        stripQuarantine(dest)
        AKLogInfo("install", "installed -> \(dest.path)")
        return dest
    }

    public static func stripQuarantine(_ url: URL) {
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", url.path])
    }

    // MARK: 备份 / 回滚

    public static func backup(_ app: URL, to root: URL) throws {
        let version = Scanner.readApp(at: app)?.displayVersion ?? "unknown"
        let dir = root.appendingPathComponent(app.deletingPathExtension().lastPathComponent, isDirectory: true)
            .appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (code, out) = Shell.run("/usr/bin/ditto", [app.path, dir.appendingPathComponent(app.lastPathComponent).path])
        guard code == 0 else { throw InstallerError.installFailed("备份失败 \(out)") }
        AKLogInfo("install", "backup \(app.lastPathComponent) @\(version)")
    }

    public static func backups(for toolName: String, root: URL) -> [URL] {
        let dir = root.appendingPathComponent(toolName, isDirectory: true)
        guard let kids = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return kids.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
    }

    public static func pruneBackups(for toolName: String, root: URL, keep: Int) {
        let all = backups(for: toolName, root: root)
        guard all.count > keep, keep >= 0 else { return }
        for old in all.dropFirst(keep) { try? FileManager.default.removeItem(at: old) }
    }

    // MARK: 卸载

    public static func uninstall(_ app: URL, bundleId: String?, alsoSupportFiles: Bool) throws {
        if let bundleId {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: bundleId) {
                running.terminate()
            }
            Thread.sleep(forTimeInterval: 0.4)
        }
        try FileManager.default.trashItem(at: app, resultingItemURL: nil)
        AKLogInfo("install", "trashed \(app.path)")

        guard alsoSupportFiles, let bundleId else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let targets = [
            AKPaths.support.deletingLastPathComponent().appendingPathComponent(bundleId),
            home.appendingPathComponent("Library/Preferences/\(bundleId).plist"),
            home.appendingPathComponent("Library/Caches/\(bundleId)"),
            home.appendingPathComponent("Library/Saved Application State/\(bundleId).savedState"),
            home.appendingPathComponent("Library/HTTPStorages/\(bundleId)"),
        ]
        for t in targets where FileManager.default.fileExists(atPath: t.path) {
            try? FileManager.default.trashItem(at: t, resultingItemURL: nil)
        }
    }

    // MARK: 运行中替换

    /// 目标 app 正在运行时，用延迟脚本完成替换（app 不能覆盖自己的 bundle）
    public static func replaceWhileRunning(newApp: URL, target: URL, relaunch: Bool) throws {
        let script = """
        #!/bin/sh
        TARGET="\(target.path)"
        NEW="\(newApp.path)"
        while pgrep -f "$TARGET/Contents/MacOS/" >/dev/null 2>&1; do sleep 0.3; done
        sleep 0.2
        rm -rf "$TARGET"
        /usr/bin/ditto "$NEW" "$TARGET"
        /usr/bin/xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
        \(relaunch ? "open \"$TARGET\"" : "true")
        rm -f "$0"
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("akit-swap-\(UUID().uuidString.prefix(8)).sh")
        try script.write(to: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [path.path]
        try p.run()
        AKLogInfo("install", "swap scheduled -> \(target.path)")
    }

    // MARK: Dev 模式重建

    /// 从源码重建并返回构建产物 .app
    public static func rebuild(spec: ToolSpec, progress: @escaping (String) -> Void) throws -> URL {
        guard let source = spec.source else { throw InstallerError.buildFailed("没有配置本地源码") }
        let root = AKPaths.expand(source.path)
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw InstallerError.buildFailed("源码目录不存在：\(root.path)")
        }

        let script = root.appendingPathComponent("Scripts/build.sh")
        let hasScript = FileManager.default.fileExists(atPath: script.path)

        progress("开始构建 \(spec.name)…")
        let result: (Int32, String)
        if let custom = source.build, !custom.isEmpty {
            result = Shell.runShell(custom, cwd: root)
        } else if hasScript {
            result = Shell.runShell("bash Scripts/build.sh", cwd: root)
        } else {
            result = Shell.runShell("swift build -c release", cwd: root)
        }
        guard result.0 == 0 else {
            throw InstallerError.buildFailed(String(result.1.suffix(1200)))
        }

        if let rel = source.appPath {
            let app = root.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: app.path) { return app }
        }
        guard let app = newestApp(under: root) else {
            throw InstallerError.buildFailed("构建成功，但没找到 .app 产物（可在清单里指定 appPath）")
        }
        progress("构建完成：\(app.lastPathComponent)")
        return app
    }

    /// 找源码目录里最新的 .app（跳过依赖缓存）
    public static func newestApp(under root: URL) -> URL? {
        let fm = FileManager.default
        var best: (URL, Date)? = nil
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                    options: [.skipsHiddenFiles]) else { return nil }
        for case let f as URL in e where f.pathExtension == "app" {
            let path = f.path
            if path.contains("/.build/checkouts/") || path.contains("/node_modules/") { continue }
            if path.contains("/Backups/") { continue }
            let d = (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if best == nil || d > best!.1 { best = (f, d) }
        }
        return best?.0
    }
}
