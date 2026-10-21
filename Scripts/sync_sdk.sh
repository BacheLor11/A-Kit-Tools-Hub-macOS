#!/usr/bin/env bash
# 把源码里的 SDK 同步到 SDK/ 目录（分发给别人用）
set -euo pipefail
cd "$(dirname "$0")/.."
cp Sources/AKitStatusKit/AKitStatusKit.swift SDK/AKitStatusKit.swift
echo "✓ SDK/AKitStatusKit.swift 已同步（$(wc -l < SDK/AKitStatusKit.swift | tr -d ' ') 行）"
