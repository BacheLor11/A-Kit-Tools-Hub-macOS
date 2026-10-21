import Foundation
import AKitCore

/// Dev 模式热重载：盯着源码目录，改完文件就重建 + 重启。
///
/// 为什么不用 FSEvents：需要 C 回调 + 上下文管理，而 SwiftPM 工程目录通常只有几百个文件，
/// 两秒轮询一次的代价远小于一个漏掉的事件导致「改了没反应」。
/// 只在「设置 → 开发者 → 自动重建」打开时工作。
final class DevWatcher {

    /// 需要跳过的目录：构建产物、依赖缓存、版本库
    private static let skipNames: Set<String> = [
        ".build", "build", ".git", "node_modules", "DerivedData",
        "Backups", ".swiftpm", "Pods", ".venv", "venv", "__pycache__",
    ]

    private struct Snapshot: Equatable {
        var newest: Date
        var count: Int
    }

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "app.askb.akit.devwatch", qos: .utility)
    private var roots: [String: URL] = [:]
    private var snapshots: [String: Snapshot] = [:]
    private var cooldown: [String: Date] = [:]

    /// 某个工具的源码变了（已经过防抖）
    var onRebuild: ((String) -> Void)?

    var isRunning: Bool { timer != nil }

    func update(roots: [String: URL]) {
        queue.async {
            self.roots = roots.filter { FileManager.default.fileExists(atPath: $0.value.path) }
            // 丢掉已经不看的
            self.snapshots = self.snapshots.filter { self.roots[$0.key] != nil }
            // 先记录当前状态，避免刚启动就误判成「有改动」
            for (id, url) in self.roots where self.snapshots[id] == nil {
                self.snapshots[id] = Self.snapshot(of: url)
            }
        }
    }

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 2)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        queue.async {
            self.snapshots.removeAll()
            self.cooldown.removeAll()
        }
    }

    private func tick() {
        let now = Date()
        for (id, url) in roots {
            guard let snap = Self.snapshot(of: url) else { continue }
            let old = snapshots[id]
            snapshots[id] = snap
            guard let old, old != snap else { continue }
            if let until = cooldown[id], until > now { continue }
            cooldown[id] = now.addingTimeInterval(10)
            AKLogInfo("dev", "检测到 \(id) 源码变化（\(old.count) → \(snap.count) 个文件）")
            DispatchQueue.main.async { self.onRebuild?(id) }
        }
    }

    // MARK: 目录指纹

    private static func snapshot(of root: URL) -> Snapshot? {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root,
                                    includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                    options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return nil
        }
        var newest = Date.distantPast
        var count = 0
        for case let f as URL in e {
            let name = f.lastPathComponent
            if skipNames.contains(name) {
                e.skipDescendants()
                continue
            }
            if f.pathExtension == "app" {
                e.skipDescendants()
                continue
            }
            let v = try? f.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            if v?.isDirectory == true { continue }
            if let d = v?.contentModificationDate, d > newest { newest = d }
            count += 1
            if count > 6000 { break }   // 兜底，避免超大仓库拖慢
        }
        return Snapshot(newest: newest, count: count)
    }
}
