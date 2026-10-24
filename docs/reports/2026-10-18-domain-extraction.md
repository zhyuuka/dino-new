# Domain 层抽取报告：生存 / 战斗 / 成长数值脱机化

- 日期：2026-10-18
- 范围：`scripts/player/PlayerDino.gd`、`scripts/ai/AIDino.gd`
- 目标：把内嵌在 Node 脚本里的数值规则抽成可脱机测试的纯逻辑层，行为逐项等价
- 约束遵守：未改 `Main.gd`、存档系统与任何 `.uid` 文件；未执行 git 写命令

## 1. 背景

`PlayerDino`（原 899 行）承担移动/相机、体力、生存衰减、咬击、拖尸、技能、进食成长、产蛋、受伤死亡等 13 类职责；
`AIDino`（原 721 行）承担决策/行为/生存/繁殖/战斗/感知/领地。两者都把下列数值规则直接写在 Node 生命周期里：

- 饥饿 / 口渴衰减间隔与饿死 / 渴死伤害（Player 14s/12s/5s/4s，AI 50s/45s/6s）
- 体力消耗 22/s、回复 14/s、力竭锁 18、叼尸 ×1.5、饮水 45/s（AI 40/s）
- 咬击伤害的成长 / 集群 / 冲锋取整顺序
- 猎食与反击的体型阈值 0.7 / 0.85 / 0.9
- 成长阶段倍率表与 `need` 边界

这些规则依赖 `get_tree()`、输入与物理帧，无法脱机验证；本次抽取后 Domain 不访问任何 Node / 输入 / 时间 / 随机数。

## 2. 做法

### 2.1 Vitals（纯逻辑生存数值）

- 新增 `scripts/domain/Vitals.gd`，`class_name Vitals extends RefCounted`。
- 状态只保留整数 `hunger / thirst / stamina` 与内部 `float` 累加器；上限和全部速率由 `setup()` 注入，Domain 内不出现 14/12/22/45 等平衡常量。
- 提供 `tick(delta, sprinting, dragging)` 完整结算，同时拆出 `tick_stamina()` / `tick_survival()`：
  - Player 原实现是“帧内先体力、后口渴”，拆分后调用顺序与旧代码完全一致；
  - AI 只调用 `tick_survival()`，不产生体力状态。
- `survival_step_once` 注入开关用于复刻两种旧写法：
  - `false`（Player）：`delta / interval` 小数累加，大 delta 可一次扣多点；
  - `true`（AI）：秒表累加，每帧最多扣 1 点，与旧 `hunger_timer / thirst_timer` 逐帧相减一致。
- 饿死 / 渴死伤害不直接调用 `take_damage`，而是累积到待结算值，由 Node 用 `pull_starve_damage()` / `pull_thirst_damage()` 拉取，保留受伤表现与死亡流程在 Node。
- 饮水、进食、回体力、扣饥饿分别走 `drink()` / `eat(kind)` / `restore_stamina()` / `consume_hunger()`，均只改整数状态。
- `has_changed()` 反映最近一次 tick 是否发生整数变化；`get_state()` 返回三项数值与上限。

### 2.2 CombatRules（战斗纯规则）

新增 `scripts/domain/CombatRules.gd`，全部 `static` 纯函数，常量从旧代码原样提取：

- `bite_damage(base, growth_mult, charge, pack_bonus)`：先成长、再集群、最后冲锋，每步 `round` 后转 `int`；
- `can_hunt(attacker_size, target_size, attacker_diet, target_diet)`：草食目标恒可猎，肉食目标需 `< 攻击者 ×0.9`，非肉食攻击者不猎；
- `can_counter(attacker_size, target_size)`：攻击者 `<= 自己 ×0.9` 可反击；
- 附带 `apply_defense()` / `apply_multiplier()` / `is_weak_prey()` / `is_threat()`，把 0.55 减伤、1.3 临时增益、0.7 弱小、0.85 威胁也收进同一层。

### 2.3 GrowthRules（成长纯规则）

新增 `scripts/domain/GrowthRules.gd`，数据源仍为 `DinoSpecies.GROWTH_STAGES`（纯静态数据类）：

- `stage_multiplier(stage, key)`：`hp/dmg/spd/size` 倍率，stage 越界由 `stage_info` 钳制，非法 key 回退 1.0；
- `next_stage_progress(stage)`：返回该阶段 `need`，霸主返回占位大数 999999（保持原进度信号逻辑）；
- `stage_index_for_progress(progress)`：把“跨阶段累计进食格数”映射到阶段下标；
- `add_progress(current, meal_kind)`：当前肉 / 植物 / 击杀均为 +1 格（原 `kill_made` 全项目无 emit，击杀本就不加成长），保留分支便于未来只改此处。

### 2.4 Node 改造原则

- `current_hunger / current_thirst / current_stamina` 改成只读属性 getter，public 名称不变；HUD、TutorialGuide 等现有读取点零改动。
- 所有 `*_changed` 信号保持原签名与节流逻辑：仍由 Node 的 `_last_*` 比较后 emit。
- Area3D 命中、动画、音效、死亡、产蛋、存档等强 Node 逻辑留在原处；只把“算数值”交给 Domain。

## 3. 改动清单（含行号）

### 新增

| 文件 | 关键内容 |
|---|---|
| `scripts/domain/Vitals.gd` | `setup` L65、`tick` L88、`tick_stamina` L95、`tick_survival` L101、`has_changed` L107、`get_state` L112、`drink` L124、`eat` L133、`restore_stamina` L145、`consume_hunger` L150、`pull_starve_damage` L155、`pull_thirst_damage` L162、`can_sprint` L169、内部结算 L180-235、状态写入 L238-296 |
| `scripts/domain/CombatRules.gd` | 阈值常量 L9-22、`bite_damage` L30、`can_hunt` L41、`can_counter` L51、`apply_defense` L56、`apply_multiplier` L61、`is_weak_prey` L66、`is_threat` L71 |
| `scripts/domain/GrowthRules.gd` | 食物类型常量 L9-14、`stage_multiplier` L19、`next_stage_progress` L28、`stage_index_for_progress` L34、`add_progress` L47 |

### 修改：`scripts/player/PlayerDino.gd`（899 → 876 行）

| 行号 | 改动 |
|---|---|
| L30-61 | 删除 `CHARGE_DMG_MULT / PACK_DMG_BONUS / DEFENSE_REDUCTION`（统一收进 CombatRules）；速率常量保留并注入 |
| L88-101 | 新增 `_vitals` 实例；`current_hunger / current_thirst / current_stamina` 改为 getter |
| L133-137 | 删除 `_hunger_acc / _thirst_acc / _stamina_acc / _drink_acc` 与饿死计时器 |
| L200 | `_ready` 注入上限与速率 |
| L222-237 | 成长属性与进度信号改调 `GrowthRules` |
| L241-260 | 新增 `_vitals_rates()`，逐项注入旧常量 |
| L347 | 饮水改 `_vitals.drink(delta)` |
| L400-407 | 体力改 `_vitals.tick_stamina()`；`can_sprint()` 委托 Vitals |
| L412-422 | 生存衰减改 `_vitals.tick_survival()` + 拉取饿死/渴死伤害 |
| L526-530 | `_effective_bite()` 改调 `CombatRules.bite_damage / apply_multiplier` |
| L626 | `restore_stamina` 委托 Vitals |
| L652 | 冲锋伤害改调 `CombatRules.bite_damage(..., charge=true, ...)` |
| L671-688 | 肉 / 植物进食改 `_vitals.eat()`，成长累加带 meal_kind |
| L696-698 | 成长累加改 `GrowthRules.add_progress / next_stage_progress` |
| L748 | 产蛋扣饥饿改 `_vitals.consume_hunger()` |
| L767 | 重甲减伤改 `CombatRules.apply_defense()` |

### 修改：`scripts/ai/AIDino.gd`（721 → 730 行）

| 行号 | 改动 |
|---|---|
| L66-76 | 新增 `_vitals`；`current_hunger / current_thirst` 改为 getter |
| L83-85 | 删除 `hunger_timer / thirst_timer / _drink_acc / starve_timer` |
| L124 | `_ready` 注入上限与速率（体力上限 0） |
| L128-135 | 属性改调 `GrowthRules.stage_multiplier` |
| L139-158 | 新增 `_vitals_rates()`；`survival_step_once = true` 保持旧秒表语义 |
| L263-267 | `_prey_weak` 改调 `CombatRules.is_weak_prey` |
| L330-336 | `_can_beat_attacker` 改调 `CombatRules.can_counter` |
| L457 | AI 饮水改 `_vitals.drink(delta)` |
| L473-477 | 生存衰减改 `tick_survival` + 拉取饿死伤害 |
| L481-484 | `_eat(kind, heal)` 改 `_vitals.eat(kind)`；调用点 L406 / L415 / L489 同步 |
| L541 | 重甲减伤改 `CombatRules.apply_defense()` |
| L557-562 | `_effective_bite()` 改调 `CombatRules.bite_damage` |
| L594 / L601 | 威胁判定改调 `CombatRules.is_threat`（0.85 阈值） |
| L638 / L672 | 猎食判定改调 `CombatRules.can_hunt`（0.9 阈值，草食恒可猎） |

### 修改：`tests/run_tests.gd`（165 → 407 行）

| 行号 | 改动 |
|---|---|
| L20-22 | 挂载三个新测试组 |
| L174-206 | 测试侧速率字典与 60fps 逐帧助手 |
| L208-326 | Vitals 35 条断言（45s 衰减、冲刺/叼尸体力、力竭锁、饮水、进食、3600 帧、饿死/渴死、AI 秒表模式） |
| L331-364 | CombatRules 20 条断言（体型阈值、冲锋、集群、减伤、威胁/弱小） |
| L369-407 | GrowthRules 28 条断言（越界钳制、need、累计进度边界、进度累加） |

## 4. 等价性对照表

| 规则 | 旧实现 | 新实现 | 结论 |
|---|---|---|---|
| Player 饥饿 | `_hunger_acc += delta/14`，满 1 扣 1 | `Vitals._tick_survival` 同式累加，`survival_step_once=false` | 逐帧等价 |
| Player 口渴冲刺 | 间隔 `12 * 0.5` | 同为 `12 * 0.5`，由 rates 注入 | 等价 |
| Player 饿死/渴死 | 5s/6 点、4s/5 点，`if` 每帧最多一次 | 同间隔同伤害，待结算伤害由 Node 调 `take_damage` | 等价（同帧两次伤害仍按先饥饿后口渴） |
| Player 体力 | 22/s 扣、14/s 回、叼尸 ×1.5、力竭锁 18 | Vitals 同速率同累加器；`_update_exhausted` 位置不变 | 等价 |
| Player 饮水 | `45 * delta` 累加 | `Vitals.drink` 同式 | 等价 |
| Player 进食 | 肉 +28、植物 +10/+4 | `rates` 注入同值 | 等价 |
| Player 咬击 | 集群 `round(*1.2)` → 临时增益 `round(*buff)` | `CombatRules` 先成长再集群，Node 再 `apply_multiplier` | 取整顺序与结果等价 |
| Player 冲锋 | `round(有效咬击 × 2.2)` | `CombatRules.bite_damage(..., charge=true)` | 等价 |
| Player 重甲 | `round(amount × 0.55)` | `CombatRules.apply_defense()` | 等价 |
| AI 饥饿/口渴 | 50s / 45s 秒表，每帧最多 1 点 | `survival_step_once=true` 复刻秒表 | 等价（含大 delta） |
| AI 饮水 | 40/s 累加 | `rates` 注入 40 | 等价 |
| AI 进食 | 肉 +30、植物 +12、蛋 +10 | `eat("meat"/"plant"/"egg")` 注入同值 | 等价 |
| AI 猎食 | 草食恒可猎；肉食 `< ×0.9` | `CombatRules.can_hunt` 同式，且仅肉食调用方使用 | 等价 |
| AI 反击 | `attacker <= self ×0.9` | `CombatRules.can_counter` | 等价 |
| AI 威胁/弱小 | 0.85 / 0.7 | `CombatRules.is_threat / is_weak_prey` | 等价 |
| 成长倍率 | `stage_info[hp/dmg/spd/size]` | `GrowthRules.stage_multiplier` 同源同表 | 等价 |
| 成长进度 | `growth_meals += 1`，`>= need` 升阶 | `add_progress(+1)` + `next_stage_progress` 同表 | 等价 |
| 成长信号 | `need < 9000 → meals/need，否则 1.0` | `next_stage_progress` 返回 999999，判据不变 | 等价 |
| public 成员 | `current_hunger` 等可读写变量 | 只读 getter，名称/类型不变 | 读取方零改动；无外部写入点 |

## 5. 验证结果

### 5.1 导入（要求 SCRIPT ERROR = 0）

```bash
XDG_DATA_HOME=/workspace/tools/godotdata XDG_CONFIG_HOME=/workspace/tools/godotconfig \
/workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path /workspace/dino-new --import
```

- 进程退出码 0
- `grep -c "SCRIPT ERROR"` → `0`
- 全局类注册成功：`AIDino / CombatRules / GrowthRules / Vitals / PlayerDino`
- 仅有 Android 调试桥不可用的环境提示 `cannot connect to daemon at tcp:5037`，与本改动无关

### 5.2 单元测试

```bash
XDG_DATA_HOME=/workspace/tools/godotdata XDG_CONFIG_HOME=/workspace/tools/godotconfig \
/workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path /workspace/dino-new \
-s res://tests/run_tests.gd
```

输出：

```text
PASSED: 135 / FAILED: 0
```

- 原基线 52 条，全部仍通过
- 新增 83 条断言，覆盖任务要求的 Vitals / CombatRules / GrowthRules 场景
- 测试中的两条 `Parse JSON failed` 来自既有的“损坏存档”用例，属预期错误日志，不是失败

### 5.3 主场景冒烟

```bash
timeout 90 env ... godot --headless --path /workspace/dino-new --quit-after 60
```

- 退出码 0
- 无 `SCRIPT ERROR` / `Parse Error`
- 退出时仅有 Godot 常见的 `ObjectDB instances leaked` 提示（中途 `--quit-after` 导致，非脚本错误）

## 6. 风险

1. **速率字典缺键会运行时报错**：`Vitals` 按设计要求不提供默认平衡值，`setup()` 的 rates 必须包含文档列出的全部键。目前 Player / AI / 测试三处均已完整注入；后续新增速率需同步三处。
2. **public 变量变为只读属性**：`current_hunger / current_thirst / current_stamina` 不能再被外部赋值。全仓检索确认当前只有读取点（HUD / TutorialGuide / `_decide`），无外部写入；若未来有脚本写入会直接报错。
3. **PlayerDino 删除了三个 public 常量**：`CHARGE_DMG_MULT / PACK_DMG_BONUS / DEFENSE_REDUCTION` 已迁移到 `CombatRules`。全仓 grep 确认无其他引用；仓库外脚本若引用会失效。
4. **AI 大 delta 语义靠 `survival_step_once` 保留**：若误把 AI 的该键改成 `false`，卡顿帧会一次扣多点，与旧 AI 行为不同。Player 仍为 `false`，与旧 Player 的 `int(acc)` 一致。
5. **`stage_index_for_progress` 是新增的反查能力**：其语义为“跨阶段累计进食格数”，当前游戏内并未使用（Player 仍按阶段内计数升阶，以保证完全等价），仅测试与未来逻辑使用。若未来改用它驱动升阶，需确认累计/阶段内两种口径不会混用。
6. **未做存档字段变更**：`current_hunger` 等本来就不入档，本次未触碰存档系统，旧档兼容。

## 7. 回退方式

本轮不涉及存档格式、场景资源、UID 或 autoload，可整层回退：

1. 删除 `scripts/domain/`（`Vitals.gd`、`CombatRules.gd`、`GrowthRules.gd`）；
2. 回退三个修改文件：
   - `git checkout -- scripts/player/PlayerDino.gd scripts/ai/AIDino.gd tests/run_tests.gd`
3. 重新执行 `--import` 与单测。

回退后行为与改动前一致，无需迁移存档或重建场景。本次未执行任何 git 写命令，改动均留在工作区。

## 8. 引用来源

- `scripts/player/PlayerDino.gd` L30-84（原速率常量）、L88-150（原状态/累加器）、L222-243（成长）、L344-347（饮水）、L398-457（体力/生存）、L525-530（咬击）、L623-626（回体）、L646-651（冲锋）、L670-708（进食成长）、L743-748（产蛋）、L761-767（受伤）
- `scripts/ai/AIDino.gd` L25-57（原速率/进食）、L66-90（原状态/计时器）、L128-136（属性）、L262-267（弱小）、L328-336（反击）、L444-457（饮水）、L471-489（生存/进食）、L529-541（受伤）、L556-562（咬击）、L579-604（威胁）、L628-675（猎食）
- `scripts/data/DinoSpecies.gd` L27-34（成长阶段表与 `MAX_STAGE`）
- `docs/README.md`（子代理报告规范：背景/做法/改动清单/验证/风险/回退/引用）
