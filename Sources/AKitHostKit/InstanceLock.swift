import Foundation

/// 单实例锁。
///
/// 插件和独立 app 是两个互不相干的地址空间，谁也看不见谁。
/// 但它们的引擎操作的是同一批文件——A-Sweep 两个实例同时清理同一个目录，
/// 这不是性能问题，是数据安全问题。
///
/// 所以用一把文件锁仲裁：**谁拿到锁，谁活着。**
///
/// ```swift
/// let lock = AKInstanceLock(directory: supportDir)
/// guard lock.tryAcquire() else {
///     // 别人在跑 —— 独立 app 应请求 Hub 接管后退出；插件应停在「未激活」
/// }
/// ```
public final class AKInstanceLock {

    private let url: URL
    private var fd: Int32 = -1

    public init(directory: URL) {
        self.url = directory.appendingPathComponent("instance.lock")
    }

    public var isHeld: Bool { fd >= 0 }

    deinit { release() }

    /// 非阻塞抢锁。返回 false 表示已有别的实例持有。
    @discardableResult
    public func tryAcquire() -> Bool {
        if fd >= 0 { return true }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let handle = open(url.path, O_CREAT | O_RDWR, 0o644)
        guard handle >= 0 else { return false }
        if flock(handle, LOCK_EX | LOCK_NB) != 0 {
            close(handle)
            return false
        }
        fd = handle
        // 写进自己的 pid，方便人工排查「现在是谁占着」
        let pid = "\(getpid())\n"
        ftruncate(handle, 0)
        _ = pid.withCString { write(handle, $0, strlen($0)) }
        return true
    }

    /// 当前持锁者的 pid（读文件内容，锁释放后会留着旧值，仅作参考）
    public var holderPid: pid_t? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return pid
    }

    /// 持锁进程还活着吗
    public var holderIsAlive: Bool {
        guard let pid = holderPid else { return false }
        return kill(pid, 0) == 0
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }
}
