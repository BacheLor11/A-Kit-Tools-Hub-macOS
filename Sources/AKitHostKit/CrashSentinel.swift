import Foundation

/// 崩溃哨兵。
///
/// 插件跑在宿主进程里，崩了就是宿主一起崩——没有进程隔离可言。
/// 能做的是**知道自己上次崩在哪**，下次启动把肇事插件禁掉。
///
/// 协议：
/// 1. 启动写 `{ loading: ["com.aibao.ASweep"], startedAt: ... }`
/// 2. 每成功加载一个插件，就把它从 `loading` 里挪进 `loaded`
/// 3. 正常退出删文件
/// 4. 下次启动发现文件还在 → 上次是异常退出 → `loading` 里那个就是嫌疑犯
public final class AKCrashSentinel {

    public struct State: Codable {
        public var loading: [String]
        public var loaded: [String]
        public var startedAt: Date
    }

    private let url: URL
    private var state: State

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(State.self, from: data) {
            self.state = s
        } else {
            self.state = State(loading: [], loaded: [], startedAt: Date())
        }
    }

    /// 上次异常退出时正在加载的插件（空数组 = 上次正常退出或首次启动）
    public var suspects: [String] { state.loading }

    public func begin() {
        state = State(loading: [], loaded: [], startedAt: Date())
        flush()
    }

    public func willLoad(_ pluginId: String) {
        state.loading.append(pluginId)
        flush()
    }

    public func didLoad(_ pluginId: String) {
        state.loading.removeAll { $0 == pluginId }
        if !state.loaded.contains(pluginId) { state.loaded.append(pluginId) }
        flush()
    }

    /// 正常退出
    public func clear() {
        try? FileManager.default.removeItem(at: url)
    }

    private func flush() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
