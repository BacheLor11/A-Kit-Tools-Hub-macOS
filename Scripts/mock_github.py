#!/usr/bin/env python3
"""本地假装 GitHub API，用来端到端测「从链接安装」而不消耗真实 API 额度。

用法：
  python3 Scripts/mock_github.py 8766 /tmp/akit-serve
然后：
  AKIT_GITHUB_API=http://127.0.0.1:8766 AKIT_GITHUB_RAW=http://127.0.0.1:8766 \
    ./.build/debug/akit inspect demo/MyTool
"""
import json
import pathlib
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8766
STATIC = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "/tmp/akit-serve")
BASE = f"http://127.0.0.1:{PORT}"

RELEASES = {
    "demo/MyTool": {
        "tag_name": "v1.3.0",
        "name": "MyTool 1.3.0",
        "body": "· 修了一个崩溃\n· 新增快捷键",
        "published_at": "2026-10-20T09:00:00Z",
        "prerelease": False,
        "assets": [
            {"name": "MyTool-1.3.0.zip", "browser_download_url": f"{BASE}/DemoTool-0.1.0.zip", "size": 88523},
            {"name": "MyTool-1.3.0.pkg", "browser_download_url": f"{BASE}/MyTool-1.3.0.pkg", "size": 90000},
            {"name": "Source code (zip)", "browser_download_url": f"{BASE}/src.zip", "size": 1000},
        ],
    },
    # 带 akit.json 的仓库
    "demo/WithManifest": {
        "tag_name": "v2.0.1",
        "name": "MyTool Pro 2.0.1",
        "body": "· 支持菜单栏托管",
        "published_at": "2026-10-21T02:00:00Z",
        "prerelease": False,
        "assets": [
            {"name": "MyToolPro-2.0.1-universal.zip", "browser_download_url": f"{BASE}/DemoTool-0.1.0.zip", "size": 88523},
            {"name": "MyToolPro-2.0.1-arm64.zip", "browser_download_url": f"{BASE}/DemoTool-0.1.0.zip", "size": 88000},
        ],
    },
    # 没有 release 的仓库
    "demo/Empty": None,
}

# akit.json（按 tag 提供）
MANIFESTS = {
    "demo/MyTool": None,   # 故意没有，测「无自描述」路径
    "demo/WithManifest": {
        "schemaVersion": 1,
        "id": "mytool-pro",
        "name": "MyTool Pro",
        "tagline": "带自描述的演示工具",
        "bundleId": "com.aibao.DemoTool",
        "asset": "*-universal.zip",
        "statusBar": True,
    },
}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _json(self, obj, code=200):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = self.path.split("?")[0]

        if path.startswith("/repos/") and path.endswith("/releases/latest"):
            slug = path[len("/repos/"):-len("/releases/latest")]
            rel = RELEASES.get(slug)
            if rel is None:
                return self._json({"message": "Not Found"}, 404)
            return self._json(rel)

        if path.startswith("/repos/") and "/releases/tags/" in path:
            slug = path[len("/repos/"):path.index("/releases/tags/")]
            rel = RELEASES.get(slug)
            if rel is None:
                return self._json({"message": "Not Found"}, 404)
            return self._json(rel)

        # raw：/<owner>/<repo>/<ref>/akit.json
        if path.endswith("/akit.json") or path.endswith("/tool.json"):
            parts = [p for p in path.split("/") if p]
            slug = "/".join(parts[:2])
            m = MANIFESTS.get(slug)
            if not m:
                return self._json({"message": "Not Found"}, 404)
            return self._json(m)

        # 静态文件
        f = STATIC / path.lstrip("/")
        if f.is_file():
            data = f.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        self._json({"message": "Not Found"}, 404)


if __name__ == "__main__":
    print(f"mock github api on {BASE}")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
