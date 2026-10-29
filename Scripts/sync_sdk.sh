#!/usr/bin/env bash
# 把源码里的 SDK 同步到 SDK/ 目录（分发给别人用）
set -euo pipefail
cd "$(dirname "$0")/.."
cp Sources/AKitStatusKit/AKitStatusKit.swift SDK/AKitStatusKit.swift
echo "✓ SDK/AKitStatusKit.swift 已同步（$(wc -l < SDK/AKitStatusKit.swift | tr -d ' ') 行）"
# 插件契约也要发出去：工具仓库 vendor 这一份，避免依赖整个 A-Kit 包
cp Sources/AKitPluginKit/PluginContracts.swift SDK/PluginContracts.swift
echo "✓ SDK/PluginContracts.swift 已同步（$(wc -l < SDK/PluginContracts.swift | tr -d ' ') 行）"
