# T5 — 探索资源点（巢穴 + 矿物盐）

## 目标
为 Phase 3 增加有意义的探索/资源点：
- **巢穴 NEST**：站在附近缓慢回血 + 回体力（安全休整点）。
- **矿物盐 LICK**：进入获得限时增益（伤害+速度），用于险境突围。

（骨堆等引怪机制涉及 AI 耦合，本期不做，避免引入 bug；后续可加。）

## 方案
### 新增 scripts/world/ResourcePoint.gd（+ scenes/ResourcePoint.tscn）
- `enum Type { NEST, LICK }`；`@export var point_type`。
- `_ready` 按类型用 CSG 代码构建可视化（巢=褐色环+柔光；盐=彩色盘+微光）。
- `_process`：找玩家（group "player"），在半径内施加效果：
  - NEST：用小数累加器每满 1 点调用 `player.heal` + `player.restore_stamina`（避免逐帧 <1 被 int 截断）。
  - LICK：调用 `player.apply_buff(...)`；进入时发一次横幅"矿物盐强化！"。

### scripts/player/PlayerDino.gd（增益支持）
- 新增 `buff_timer / buff_speed_mult / buff_dmg_mult`（默认 1）。
- `_physics_process` 内递减 buff_timer，归零重置倍率；基础速度 `speed *= buff_speed_mult`。
- `_effective_bite()` 结果乘以 `buff_dmg_mult`。
- 新增 `func apply_buff(dur, spd, dmg)` 与 `func restore_stamina(amt)`（夹取并 emit stamina_changed）。

### scripts/game/Main.gd
- 新增 `_spawn_resource_points()`：在地图散布 3 巢穴 + 3 矿物盐（避开水源与出生点），于 `_start_game` 调用。

## 效果预期
- 玩家探索地图能找到休整点与强化点，策略性提升。
- 增益数值合理（盐：+25% 速度 / +40% 伤害 / 30s），不破坏平衡。
- headless 运行零报错；资源点仅在玩家靠近时触发，无副作用。

## 验证
- `--quit-after 12` 无 SCRIPT ERROR / 编译错误。
- 代码审查：ResourcePoint 不依赖未定义节点；apply_buff/restore_stamina 与现有 stamina 逻辑一致。
