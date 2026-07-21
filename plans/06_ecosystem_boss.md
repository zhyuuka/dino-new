# T6 — 生态丰富 + 传奇霸主

## 目标
- 让生态种群更均衡（更多草食/猎物，兽群更明显）。
- 加入一只**游荡的传说霸主·霸王龙**（最高成长阶段），作为世界级的持续威胁；
  被击杀后一段时间会在地图边缘重新出没，保持压迫感。

## 方案（scripts/game/Main.gd）
- `_build_roster` 调整为更均衡的种群（增加 galli×3、trike×2、anky×2、raptor×3、carno×1）。
- 新增 `var boss_ai: AIDino = null` 与 `var boss_respawn_timer: float = 0.0`。
- 新增 `_spawn_boss()`：在地图边缘生成 1 只 trex（start_growth_stage=MAX_STAGE），
  接 died 信号，记录 boss_ai，发横幅"传说霸主·霸王龙 出没！"。
- `_spawn_ecosystem` 末尾调用 `_spawn_boss()`。
- `_on_ai_died`：若死亡的是 boss_ai，则置空并设 `boss_respawn_timer = 60.0`。
- `_process` 主循环中：若 `boss_ai == null` 且 `boss_respawn_timer>0`，递减；归零时 `_spawn_boss()`。

## 效果预期
- 地图始终存在一只巨型霸王龙（APEX），小型恐龙会因威压逃窜，玩家需躲避或挑战。
- 击杀后 60s 在边缘重生，世界威胁持续。
- 种群结构更丰富，兽群感更强。
- headless 运行零报错；boss 复用现有 AIDino/AI 逻辑，无副作用。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误。
- 代码审查：boss_ai 置空与重生闭环正确；AI 群体遍历安全。
