#!/usr/bin/env python3
"""生成可供 A-Kit「从链接安装 / 清单更新」使用的 manifest.json。

读 Resources/seed-manifest.json，把 A-Kit 自己作为一条工具插到最前面
（装了 A-Kit 的人可以从清单里更新 A-Kit 本身），再写出去。

用法：
  python3 Scripts/gen_manifest.py \
      --version 0.2.0 \
      --url https://github.com/BacheLor11/A-Kit/releases/download/v0.2.0/A-Kit-0.2.0.zip \
      --sha256 <hex> \
      --notes "本次更新…" \
      --out manifest.json
"""
import argparse
import json
import plistlib
import pathlib
import sys
from datetime import date

ROOT = pathlib.Path(__file__).resolve().parent.parent
SEED = ROOT / "Resources" / "seed-manifest.json"
INFO = ROOT / "Resources" / "Info.plist"


def read_bundle_id() -> str:
    try:
        with open(INFO, "rb") as f:
            return plistlib.load(f).get("CFBundleIdentifier", "com.aibao.AKitHub")
    except Exception:
        return "com.aibao.AKitHub"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--sha256", default="")
    ap.add_argument("--notes", default="")
    ap.add_argument("--min-os", default="13.0")
    ap.add_argument("--out", default="manifest.json")
    args = ap.parse_args()

    tools = []
    if SEED.exists():
        seed = json.loads(SEED.read_text(encoding="utf-8"))
        tools = seed.get("tools", [])

    # 去掉旧的 A-Kit 条目，避免重复
    tools = [t for t in tools if t.get("id") != "akit"]

    tools.insert(0, {
        "id": "akit",
        "name": "A-Kit",
        "tagline": "自己写的小工具，自己收着。",
        "bundleId": read_bundle_id(),
        "category": "tool",
        "repo": "BacheLor11/A-Kit",
        "statusBar": {"supported": True, "defaultVisible": True},
        "channels": {
            "stable": {
                "version": args.version.lstrip("v"),
                "minOS": args.min_os,
                "url": args.url,
                "sha256": args.sha256,
                "notes": args.notes,
                "releasedAt": date.today().isoformat(),
            }
        },
    })

    manifest = {
        "schemaVersion": 1,
        "generatedAt": date.today().isoformat(),
        "tools": tools,
    }

    out = pathlib.Path(args.out)
    out.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"✓ {out} · {len(tools)} 个工具 · A-Kit {args.version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
