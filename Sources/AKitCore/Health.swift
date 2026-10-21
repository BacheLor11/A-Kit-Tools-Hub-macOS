import Foundation

// MARK: - 体检

public struct HealthReport {
    public var signed = false
    public var signer = "—"
    public var teamId = "—"
    public var hardened = false
    public var notarized = false
    public var gatekeeper = "未知"
    public var minOS = "—"
    public var quarantined = false
    public var architectures: [String] = []
    public var warnings: [String] = []
    public var passed: Bool { warnings.isEmpty }

    public init() {}
}

public enum Health {
    public static func check(_ app: InstalledApp) -> HealthReport {
        var r = HealthReport()
        let bundle = app.path

        let (csCode, csOut) = Shell.run("/usr/bin/codesign", ["-dv", "--verbose=4", bundle.path])
        r.signed = csCode == 0
        if csOut.contains("Signature=adhoc") {
            r.signer = "ad-hoc（未使用开发者证书）"
            r.warnings.append("使用 ad-hoc 签名：换机器或发给别人时会被 Gatekeeper 拦截")
        }
        for line in csOut.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("Authority=") {
                let v = s.replacingOccurrences(of: "Authority=", with: "")
                if r.signer == "—" || r.signer.hasPrefix("ad-hoc") { r.signer = v }
            } else if s.hasPrefix("TeamIdentifier=") {
                r.teamId = s.replacingOccurrences(of: "TeamIdentifier=", with: "")
            } else if s.contains("flags=") && s.contains("runtime") {
                r.hardened = true
            } else if s.hasPrefix("Runtime Version=") {
                r.hardened = true
            }
        }
        if !r.signed { r.warnings.append("未签名，系统可能直接拒绝运行") }
        if r.signed && !r.hardened && !r.signer.hasPrefix("ad-hoc") {
            r.warnings.append("缺少 Hardened Runtime，无法通过公证")
        }

        let (spCode, spOut) = Shell.run("/usr/sbin/spctl", ["-a", "-vv", "-t", "exec", bundle.path])
        r.notarized = spCode == 0 && spOut.contains("Notarized")
        r.gatekeeper = spCode == 0 ? "通过" : "未通过"

        let (_, xattrOut) = Shell.run("/usr/bin/xattr", ["-p", "com.apple.quarantine", bundle.path])
        r.quarantined = !xattrOut.contains("No such") && !xattrOut.isEmpty

        let exeName = (Bundle(url: bundle)?.object(forInfoDictionaryKey: "CFBundleExecutable") as? String) ?? ""
        let exe = bundle.appendingPathComponent("Contents/MacOS/\(exeName)")
        if FileManager.default.fileExists(atPath: exe.path) {
            let (_, archOut) = Shell.run("/usr/bin/lipo", ["-archs", exe.path])
            r.architectures = archOut.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if !r.architectures.isEmpty && !r.architectures.contains("arm64") {
                r.warnings.append("只有 \(r.architectures.joined(separator: "/")) 架构，在 Apple Silicon 上走 Rosetta")
            }
        } else {
            r.warnings.append("找不到可执行文件，bundle 可能不完整")
        }

        r.minOS = (Bundle(url: bundle)?.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String) ?? "—"

        if let minOS = Double(r.minOS), minOS > 26.0 {
            r.warnings.append("最低系统要求 \(r.minOS)，低版本机器装不上")
        }

        return r
    }
}

// MARK: - 清单加载

public enum ManifestStore {
    public static func loadCache() -> Manifest? {
        guard let data = try? Data(contentsOf: AKPaths.manifestCache) else { return nil }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    public static func saveCache(_ m: Manifest) {
        AKPaths.ensure()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(m) { try? data.write(to: AKPaths.manifestCache) }
    }

    /// 内置清单：Resources/seed-manifest.json（随 app 分发）
    public static func loadBundled() -> Manifest? {
        let cwdSeed = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/seed-manifest.json")
        let candidates = [
            Bundle.main.url(forResource: "seed-manifest", withExtension: "json"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/seed-manifest.json"),
            cwdSeed,
        ].compactMap { $0 }
        for url in candidates {
            if let data = try? Data(contentsOf: url),
               let m = try? JSONDecoder().decode(Manifest.self, from: data) {
                return m
            }
        }
        return nil
    }

    public static func loadRemote(_ urlString: String) async throws -> Manifest {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("A-Kit/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        saveCache(manifest)
        return manifest
    }
}
