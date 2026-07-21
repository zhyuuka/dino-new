# T4 — 地图扩张 + 多水源 + 边界 + 植被丰富

## 目标
完成 Phase 3 地图扩张：可玩区域大幅扩大（约 4 倍），散布多个水源，植被更密并出现树林集群，
且玩家被边界正确限制（此前玩家无边界钳制，可走出地图）。

## 方案
### scenes/Main.tscn
- 地面 `Floor` 与 `shape_floor`：160 → 280（半边长 140）。
- 干涸地块 `DryPatch`/`shape_dry`：70 → 110，偏移到 (55,0.05,-55)。
- 四面边界墙 `Wall{N,S,E,W}`：位置 ±80 → ±140；对应 shape 长度 160 → 280。

### scripts/game/Main.gd
- `MAP_RADIUS` 78 → 135（圆形半径，略小于方形半边长 140）。
- 新增 `WATER_POINTS: Array` = [主湖(-40,40,r18), 池塘(60,-55,r12), 池塘(-75,-65,r10)]。
- `_spawn_water()` 遍历 WATER_POINTS 逐个生成 WaterSource（保留现有接口）。
- `_spawn_decor()`：树 20→34、岩石 12→22；额外生成 3 处"树林集群"（每处 5-7 棵树聚拢）。
- `_random_ground_pos()` 已用 MAP_RADIUS，自动适配。

### scripts/player/PlayerDino.gd
- 新增 `var map_radius: float = 140.0`（由 Main 在 add_child 前赋值）。
- `_physics_process` 末尾 `move_and_slide()` 后：若离中心 > map_radius，拉回边界并清零越界速度。

### scripts/world/FoliageSpawner.gd
- `SPAWN_RADIUS` 70 → 130（植物覆盖更大地图）。

## 效果预期
- 地图明显更大、植被更密、有多个喝水点；玩家无法走出边界（被墙挡住/钳制）。
- AI 边界逻辑不变（仍用 map_radius）。
- headless 运行零报错；无回归（地面/墙碰撞正常）。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误。
- 代码审查：WATER_POINTS 生成的水源均加入 "water" 组（WaterSource._ready 已做）；
  玩家钳制不改变速度外的逻辑。
