import Foundation
import AKitCore
import AKitStatusKit

/// 监听 Unix domain socket，接自家工具注册上来的菜单。
/// 协议：换行分隔的 JSON（JSON-RPC 风格）。
final class HubServer {
    struct Client {
        var fd: Int32
        var info: AKToolInfo
        var source: DispatchSourceRead?
        var buffer = Data()
    }

    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [String: Client] = [:]
    private let queue = DispatchQueue(label: "app.askb.akit.hubserver")

    /// 连接集合变化（注册 / 断开 / 菜单更新）
    var onClientsChanged: (() -> Void)?
    /// 只是某工具的状态文字变了（轻量通道，不重建条目）
    var onStatusChanged: ((_ bundleId: String, _ status: String) -> Void)?
    /// 外部要求打开某个工具的独立窗口（`openWindow` 方法）
    var onOpenPluginWindow: ((String) -> Void)?
    /// 某个工具发来事件（用于界面展示 / 转发）
    var onEvent: ((_ name: String, _ payload: [String: String], _ from: String?) -> Void)?

    var connectedTools: [AKToolInfo] {
        queue.sync { clients.values.map { $0.info } }
    }

    var isListening: Bool { listenFD >= 0 }

    // MARK: 生命周期

    func start() {
        AKPaths.ensure()
        let path = ProcessInfo.processInfo.environment["AKIT_SOCKET_PATH"] ?? AKPaths.socket.path

        // 已经有一个 Hub 在监听就绝不 unlink —— 否则会把活着的实例「断网」：
        // 它的监听 fd 还开着，但文件已经指向别处，之后所有工具都连不上。
        if Self.isLive(path) {
            AKLogInfo("hub", "已有实例在监听 \(path)，本进程不接管")
            return
        }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            AKLogInfo("hub", "socket() 失败")
            return
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) { p in
                p.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    _ = strlcpy(dst, cs, maxLen)
                }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bindPtr in
                bind(fd, bindPtr, size)
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            AKLogInfo("hub", "bind/listen 失败 errno=\(errno)")
            close(fd)
            return
        }
        // 必须非阻塞：否则 accept 完最后一个连接后会阻塞住串行队列，
        // 后面所有客户端的读事件都排不上队（曾经踩过这个坑）
        fcntl(fd, F_SETFL, O_NONBLOCK)
        listenFD = fd

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        src.setEventHandler { [weak self] in self?.acceptPending() }
        src.resume()
        acceptSource = src
        AKLogInfo("hub", "listening \(path)")
    }

    func stop() {
        queue.sync {
            for (_, c) in clients {
                c.source?.cancel()
                close(c.fd)
            }
            clients.removeAll()
            acceptSource?.cancel()
            acceptSource = nil
            if listenFD >= 0 { close(listenFD); listenFD = -1 }
            unlink(AKPaths.socket.path)
        }
    }

    // MARK: 接受连接

    /// 这个 socket 路径上有没有活着的监听者（能 connect 上就说明有）
    static func isLive(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        path.withCString { cs in
            withUnsafeMutablePointer(to: &addr.sun_path) { p in
                p.withMemoryRebound(to: CChar.self, capacity: maxLen) { dst in
                    _ = strlcpy(dst, cs, maxLen)
                }
            }
        }
        let size = socklen_t(MemoryLayout<sockaddr_un>.size)
        let r = withUnsafePointer(to: &addr) { p -> Int32 in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { sp in
                Darwin.connect(fd, sp, size)
            }
        }
        return r == 0
    }

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            if fd < 0 { return }
            fcntl(fd, F_SETFL, O_NONBLOCK)
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            let key = "conn-\(fd)"
            clients[key] = Client(fd: fd, info: AKToolInfo(bundleId: key, name: "未命名", version: "0"), source: src)
            src.setEventHandler { [weak self] in self?.readClient(key) }
            src.setCancelHandler { [weak self] in
                self?.dropClient(key, closeFD: true)
            }
            src.resume()
        }
    }

    private func readClient(_ key: String) {
        guard var client = clients[key] else { return }
        var buf = [UInt8](repeating: 0, count: 8192)
        let n = recv(client.fd, &buf, buf.count, 0)
        if n <= 0 {
            dropClient(key, closeFD: true)
            return
        }
        client.buffer.append(contentsOf: buf[0..<n])
        var lines: [String] = []
        while let idx = client.buffer.firstIndex(of: 0x0A) {
            let chunk = client.buffer[client.buffer.startIndex..<idx]
            client.buffer.removeSubrange(client.buffer.startIndex...idx)
            if let s = String(data: chunk, encoding: .utf8), !s.isEmpty { lines.append(s) }
        }
        clients[key] = client
        for line in lines { handle(line, key: key) }
    }

    private func handle(_ line: String, key: String) {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = obj["method"] as? String else { return }

        switch method {
        case "register":
            guard let params = obj["params"],
                  let pd = try? JSONSerialization.data(withJSONObject: params),
                  let info = try? JSONDecoder().decode(AKToolInfo.self, from: pd) else { return }
            // 同一工具重连：清掉旧连接
            for (k, c) in clients where k != key && c.info.bundleId == info.bundleId {
                c.source?.cancel()
                close(c.fd)
                clients.removeValue(forKey: k)
            }
            clients[key]?.info = info
            AKLogInfo("hub", "register \(info.name) v\(info.version) items=\(info.menu.count)")
            onClientsChanged?()
        case "status":
            // 轻量通道：只改状态文字，不动菜单，也不打日志。
            // 高频刷新的工具（CPU/内存/进度）应该走这里，否则日志与界面都会被刷爆。
            guard let params = obj["params"] as? [String: Any],
                  let text = params["status"] as? String,
                  let bundleId = clients[key]?.info.bundleId,
                  clients[key]?.info.status != text else { return }
            clients[key]?.info.status = text
            onStatusChanged?(bundleId, text)
        case "event":
            // 工具 → Hub 的事件：转发给订阅了该事件的其他工具
            let params = obj["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String, !name.isEmpty else { return }
            let payload = (params["payload"] as? [String: Any])?.reduce(into: [String: String]()) {
                $0[$1.key] = "\($1.value)"
            } ?? [:]
            let sender = clients[key]?.info.bundleId
            for c in clients.values where c.info.bundleId != sender {
                if let subs = c.info.subscribes, !subs.contains(name) { continue }
                send(["jsonrpc": "2.0", "id": UUID().uuidString, "method": "event",
                      "params": ["name": name, "payload": payload, "from": sender ?? ""]], to: c.fd)
            }
            let captured = (name, payload, sender)
            AKLogInfo("hub", "event \(name) from \(sender ?? "?")")
            DispatchQueue.main.async { [weak self] in
                self?.onEvent?(captured.0, captured.1, captured.2)
            }
        case "pong":
            break
        case "openWindow":
            // 让宿主打开某个工具的独立窗口。
            // 命令行 / 脚本 / 别的工具都可以用：一行 JSON 就行
            //   {"jsonrpc":"2.0","method":"openWindow","params":{"pluginId":"com.aibao.AKeyStats"}}
            guard let params = obj["params"] as? [String: Any],
                  let pid = params["pluginId"] as? String, !pid.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onOpenPluginWindow?(pid)
            }
        default:
            break
        }
    }

    private func dropClient(_ key: String, closeFD: Bool) {
        guard let c = clients.removeValue(forKey: key) else { return }
        c.source?.cancel()
        if closeFD { close(c.fd) }
        AKLogInfo("hub", "disconnect \(c.info.name)")
        onClientsChanged?()
    }

    // MARK: 下发

    func invoke(toolId: String, itemId: String) {
        queue.async {
            guard let c = self.clients.values.first(where: { $0.info.bundleId == toolId }) else { return }
            self.send(["jsonrpc": "2.0", "id": UUID().uuidString, "method": "invoke",
                       "params": ["itemId": itemId]], to: c.fd)
        }
    }

    /// 事件总线：把事件广播给（订阅了该事件的）工具
    func emit(_ name: String, payload: [String: String], to toolId: String? = nil) {
        queue.async {
            for c in self.clients.values {
                if let toolId, c.info.bundleId != toolId { continue }
                if toolId == nil, let subs = c.info.subscribes, !subs.contains(name) { continue }
                self.send(["jsonrpc": "2.0", "id": UUID().uuidString, "method": "event",
                           "params": ["name": name, "payload": payload]], to: c.fd)
            }
        }
    }

    private func send(_ object: [String: Any], to fd: Int32) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        var payload = data
        payload.append(0x0A)
        payload.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < payload.count {
                let n = Darwin.send(fd, base.advanced(by: sent), payload.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }
}
