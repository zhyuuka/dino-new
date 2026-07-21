# T12 — 最终 APK 导出与文档

## 目标
产出可在安卓手机安装运行的最终 debug APK；更新 PROGRESS.md / HANDOVER.md 记录完整状态。

## 方案
1. 最终无头校验：运行 16s，过滤 SCRIPT ERROR / parse / compile / Animation not found（忽略 is_inside_tree 良性警告）。
2. 导出：`godot --headless --export-debug "Android Debug" build/dino-world-debug.apk`（非 gradle 模板打包 + debug.keystore 签名）。
3. 校验产出：确认 `build/dino-world-debug.apk` 存在且大小合理；用 `aapt`/`unzip -l` 抽查 APK 内含 `classes.dex` 与 `assets`（pck 已嵌入）。
4. 更新文档：PROGRESS.md（阶段表、已交付特性、已知限制）、HANDOVER.md（当前状态、如何构建/运行、密钥与产物位置）。
5. 最终 `git add -A && git commit`。

## 效果预期
- 生成可安装的 arm64-v8a APK。
- 文档反映 T1–T12 全部完成。
- 本地 git 历史可回溯（频繁提交）。

## 验证
- 无头零错误。
- APK 文件存在且可解包（含 dex 与 assets）。
- git log 显示 T12 提交。
