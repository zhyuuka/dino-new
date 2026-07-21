# T2 — 体力 exhausted 判定修正

## 目标
消除 `_exhausted`（力竭锁定）状态滞后一帧的问题，使"体力耗尽→强制步行→回满到 18 才恢复冲刺"逻辑当帧生效。

## 方案
- `PlayerDino._update_stamina` 末尾调用 `_post_stamina_check()`（刷新 `_exhausted`），
  使随后 `_physics_process` 中 `can_sprint()` 读取的是当帧最新体力状态。
- 从 `_update_vitals` 移除重复的 `_post_stamina_check()` 调用（避免职责分散、保证单一刷新点）。

## 效果预期
- 体力降到 0 的当帧后立即无法冲刺；回升到 `STAMINA_LOCK`(18) 后才恢复冲刺资格。
- 行为正确、无延迟；不改动数值与手感。
- headless 运行零报错，无回归。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误。
- 代码审查：`_post_stamina_check` 仅由 `_update_stamina` 调用，定义顺序不影响 GDScript 方法解析。
