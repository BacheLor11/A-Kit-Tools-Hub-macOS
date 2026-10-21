import Foundation

public enum Shell {
    /// 同步跑一个命令，返回退出码与合并输出（stderr 也读，方便报错）
    @discardableResult
    public static func run(_ executable: String, _ args: [String], cwd: URL? = nil) -> (code: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return (-1, "启动失败: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        return (p.terminationStatus, out)
    }

    public static func which(_ name: String) -> String? {
        let (code, out) = run("/usr/bin/which", [name])
        guard code == 0 else { return nil }
        let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// 用登录 shell 跑命令，能拿到用户 PATH（npm/cargo 之类）
    public static func runShell(_ command: String, cwd: URL? = nil) -> (code: Int32, output: String) {
        run("/bin/zsh", ["-lc", command], cwd: cwd)
    }
}

// MARK: - 日志

public final class AKLog {
    public static let shared = AKLog()
    private let lock = NSLock()
    private var buffer: [String] = []
    private let fileURL = AKPaths.logs.appendingPathComponent("akit.log")

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    public func write(_ tag: String, _ message: String) {
        let line = "[\(formatter.string(from: Date()))] [\(tag)] \(message)"
        lock.lock()
        buffer.append(line)
        if buffer.count > 600 { buffer.removeFirst(buffer.count - 600) }
        lock.unlock()

        AKPaths.ensure()
        if let data = (line + "\n").data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
        }
    }

    public var recent: [String] {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

public func AKLogInfo(_ tag: String, _ msg: String) { AKLog.shared.write(tag, msg) }
