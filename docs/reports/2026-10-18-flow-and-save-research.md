# GameFlow 状态机与存档架构研究报告

> 研究日期：2026-10-24（文件名按任务指定为 2026-10-18）
> 代码基线：`/workspace/dino-new`（Godot 4.4.1 stable，Android，单机 3D 恐龙生存）
> 研究方式：只读代码审查 + Godot 4.4 官方文档与 2026 年公开资料查证。**未改代码、未运行 Godot。**
> 关联文档：`docs/ARCHITECTURE.md`（阶段 B/D）、`docs/PROGRESS.md`（存档双写、状态标志分散）、`HANDOVER.md`

---

## 0. 结论摘要

| 问题 | 一句话结论 | 推荐方案名 |
|---|---|---|
| 问题一：GameFlow | 本项目是“单场景、六阶段、行为很轻、重活都在加载协程里”的编排型流程，应该用**枚举 + 单一控制器 + 转移表**；状态模式与每状态一场景都会把复杂度花在本项目不需要的地方，后者还会破坏“死亡重开不重建世界”的移动端取舍。 | **六态枚举 + 单一转移表控制器（`GameFlow`，由 `Main` 持有，不新增 autoload）** |
| 问题二：存档 | 现有问题是“多处读改写 + 无迁移 + 无备份 + 未来版本静默回退后被覆盖”；应收口为**内存里 typed `PlayerProfile`、磁盘上 JSON、唯一入口 `SaveRepository`**，`Main` 成为唯一写入者，迁移链逐级纯函数化。 | **`PlayerProfile` + `SaveRepository`（JSON 持久化、原子写 + 轮换备份 + 校验和 + 迁移链）+ 单一写入者** |

两个方案共同的硬约束：**不新增 autoload**（`docs/ARCHITECTURE.md` 明确上限 4 个，当前已有 3 个）。`GameFlow` 与 `SaveRepository` 都由 `Main` 创建并注入 UI；`SaveRepository` 提供进程内 `shared()` 仅用于过渡期兼容门面。

---

## 1. 现状盘点（代码证据）

### 1.1 六个分散标志

| 标志 | 位置 | 当前语义 | 主要问题 |
|---|---|---|---|
| `Main.skip_select` | `scripts/game/Main.gd:28`、`110-114`、`604` | 静态调试开关：跳过选图/选种直接续档 | 进程级静态状态，`_on_menu` 手工复位；与“玩家是否已有档”无关；测试/冒烟脚本依赖它 |
| `Main.is_over` | `Main.gd:48`、`173`、`507-509`、`556`、`617` | 死亡展示期，阻止重复死亡与 `_process` | 与 `HUD._is_dead` 重复；只表达“死”，无法表达“死之后在等 3.5 秒”与“正在重开” |
| `Main._game_started` | `Main.gd:51`、`229`、`558`、`621` | 世界是否完整生成，门禁补员/计分/技能 | 加载中、菜单、死亡三个阶段的组合态无法枚举；`_restart_run` 需手工置 true |
| `get_tree().paused` | `PauseMenu.gd:36/42/267`、`TouchControls.gd:68-71` | 全局暂停 | 没有状态归属；任何节点都能写；场景 reload 时可能残留 true |
| `HUD._is_dead` | `HUD.gd:34`、`91`、`167` | 菜单按钮在死亡屏时直接回主菜单 | 与 `Main.is_over` 重复；HUD 自己发明流程事实 |
| `PlayerDino.is_dead` | `PlayerDino.gd:102`、`807-818` | 实体自身已死，阻止重复受伤/进食/移动 | **这是实体局部状态，应该保留**；不应升级为全局流程状态 |

> 关键判断：六个标志里，前五个是“流程事实”，第六个是“实体事实”。收敛目标不是把六个全删掉，而是把前五个收敛为一个 `GameFlow.state`，让 `PlayerDino.is_dead` 继续只做实体级幂等保护。

### 1.2 存档键散落与写入点

| 键 | 写入者（代码位置） | 读取者 | 说明 |
|---|---|---|---|
| `save_version` | `SaveManager.gd:37` | `SaveManager.gd:24` | 只拒绝更高版本，无迁移 |
| `map_id` | `Main.gd:168`、`SaveManager.gd:30-33` | `Main.gd:149`、`SpeciesSelect` 间接 | 缺省补 `Maps.DEFAULT_MAP_ID` |
| `species_id` | `Main.gd:169`、`Main.gd:512`、`PlayerDino.gd:821` | `Main.gd:161`、`SpeciesSelect.gd:18-20` | 三处写、两处读 |
| `growth_stage` | `Main.gd:168`、`Main.gd:513`、`PlayerDino.gd:822` | `Main.gd:162`、`SpeciesSelect.gd:20` | 进化时 PlayerDino 写，死亡时 Main 写 |
| `generation` | `Main.gd:168`、`Main.gd:514`、`PlayerDino.gd:823` | `Main.gd:163`、`SpeciesSelect.gd:20` | 同上 |
| `best_time` | `Main.gd:515` | `Main.gd:518` | 仅死亡时更新 |
| `best_kills` | `Main.gd:516` | `Main.gd:518` | 仅死亡时更新 |
| `tutorial_done` / `unlocked` | `Achievements.gd:116-127` | `Achievements.gd:92-113` | 独立文件 `user://achievements.json`，不在本次范围 |
| 设置键 | `GameState.gd:66-74` | `GameState.gd:41-62` | 独立文件 `user://settings.json`，不在本次范围 |

**双写丢更新路径（当前真实存在）**：

1. `PlayerDino._save_progress()`（`PlayerDino.gd:819-824`）先 `load_save()`，改 `species_id/growth_stage/generation`，再 `write_save()`。
2. `Main._on_player_died()`（`Main.gd:511-517`）也先 `load_save()`，改 `species_id/growth_stage/generation/best_*`，再 `write_save()`。
3. 两者都以“读出旧字典 → 覆盖部分字段 → 写回”的方式工作。只要执行顺序交错，后写者就可能用自己读到的旧快照覆盖前写者的新字段；`best_*` 与 `generation` 没有任何事务边界。

### 1.3 `_restart_run` 的手工清理清单

`Main.gd:528-585` 目前承担 11 项职责：

| 类别 | 项 |
|---|---|
| 释放运行期节点 | 玩家、AI（`director.clear_all`）、HUD、触屏、随机事件、尸体、选图/选种残留 |
| 重置运行期数值 | `score_keeper.reset_all()`、`is_over=false`、`_game_started=true` |
| 重建与跨代 | 读存档、找玩家蛋、销毁旧蛋、HUD/玩家/生态/事件/触屏重建、提示 |

本报告不扩大范围去重构 `_restart_run`（`RunScope` 容器是后续 P1），但要求：**改造后 `_restart_run` 只能从 `GameFlow` 的 `DEAD → PLAYING(respawn)` 一个入口进入**，内部不再读写流程布尔标志。

### 1.4 现有 `SaveManager` 的具体缺陷

| 缺陷 | 证据 | 后果 |
|---|---|---|
| 无迁移函数 | `SaveManager.gd:23-26` 只比较版本 | 结构变化只能靠 `_ensure_defaults` 兜底；旧档字段语义变化会静默错读 |
| 未来版本“回退默认”但保留原文件 | `SaveManager.gd:24-26` | 只要下一次有任何写入，未来版本档就被当前版本覆盖，属于不可逆数据破坏 |
| 无备份 | `SaveManager.gd:36-46` | 写坏/校验失败没有恢复副本 |
| 无内容校验 | 同上 | 截断或半写文件只能靠 JSON 解析失败发现；字段级损坏会被默认值吞掉 |
| 无双写保护 | `Main` / `PlayerDino` | 读改写丢更新 |
| 键名裸字符串 | 5 个文件 | 拼写错误编译期不可查 |
| 无类型/范围校验 | `_ensure_defaults` 只补 `map_id` | `growth_stage=99`、`generation=0`、未知 `species_id` 会直接进入运行期 |

---

## 2. 问题一：GameFlow 状态机

### 2.1 三种方案对比

| 维度 | 方案 A：枚举 + 单一控制器 + 转移表 | 方案 B：状态模式（每状态一个类） | 方案 C：每状态一个场景 |
|---|---|---|---|
| 适用边界 | 状态数少（≤8）、每状态行为轻、主要是“何时允许切换 + 进入/退出副作用”、单场景 | 每状态有大量独有行为、依赖、内部子状态；状态间需要多态扩展 | 各状态是完全不同的场景/关卡，切换时重建整个世界是可接受的 |
| 本项目匹配度 | **高**：六阶段只做门禁、暂停、加载、死亡重开；重活已在 `WorldBuilder`/`Main` 协程里 | 低：六个类里大部分只有 `enter()` 一行；真正复杂的加载逻辑仍要回调 Main | 极低：选图/选种/游戏共用一个 3D 世界；场景切换会重建地形/植被，违背移动端取舍 |
| 代码量 | 1 个文件，约 150 行 | 1 个容器 + 6 个类 + 基类，约 300–500 行 | 6 个 `.tscn` + 6 个脚本 + 场景间数据传递层 |
| 状态合法性 | 转移表集中，单测可 6×6 全覆盖 | 合法性分散在各状态类，容易漏 | 由场景切换 API 隐式保证，但难以穷举 |
| 调试 | 单文件 `match`，断点集中 | 调用栈跨多个类，节点/引用生命周期更长 | 跨场景断点，状态丢失 |
| 运行时成本 | 一个 Node，无额外节点 | 每状态一个 Node/RefCounted | 场景加载/释放峰值，移动端最贵 |
| 主要代价 | 单文件会随状态增多而变长；需要纪律禁止绕过转移表 | 类爆炸、依赖注入复杂、状态共享数据要走 context | 世界重建、加载界面闪烁、状态传递脆弱 |
| 结论 | **推荐** | 过度设计；可保留给 `PLAYING` 内部的玩法子模式 | 不采用 |

**明确推荐**：方案 A。若未来 `PLAYING` 内出现“游泳/飞行/骑乘”等玩法模式，再在 `PLAYING` 内用方案 B 做**子状态机**（`PlayMode`），而不是把玩法模式提升为 GameFlow 状态。

### 2.2 六态还是八态：与现有文档的差异

`docs/ARCHITECTURE.md:158` 与 `docs/PROGRESS.md:87` 写的是 8 态：`BOOT/MAP_SELECT/SPECIES_SELECT/LOADING/PLAYING/PAUSED/DEAD/MENU`。本报告建议收敛为**六态**：

```
BOOT → MENU → LOADING → PLAYING ⇄ PAUSED
                    ↘        ↘
                     MENU ←── DEAD
```

`MAP_SELECT` / `SPECIES_SELECT` 不是“游戏阶段”，而是 `MENU` 内部的两个 UI 向导页：

```gdscript
# Main 内部即可，不必放进 GameFlow
enum MenuScreen { MAP, SPECIES }
var menu_screen: MenuScreen = MenuScreen.MAP
```

理由：

1. 它们不改变暂停语义、不改变世界是否存在、不改变 `_process` 门禁，提升为状态只会让转移表从 6×6 膨胀到 8×8，并引入 `MAP_SELECT↔SPECIES_SELECT` 这类没有生命周期差异的边。
2. 选图/选种界面的“返回/重选”是 UI 导航，不是游戏阶段回退；用子视图更自然。
3. 若将来选图需要独立的 3D 预览场景，再把它提升为状态，届时转移表只需加一行。

**行动项**：落地时同步修订 `ARCHITECTURE.md` 与 `PROGRESS.md` 的 8 态描述，避免文档与代码再次分叉。

### 2.3 状态职责与转移矩阵

| 状态 | 世界是否存在 | 物理 | `_process` 计分/生态 | 典型入口 | 典型出口 |
|---|---|---|---|---|---|
| `BOOT` | 否 | 停 | 否 | 引擎启动、Main `_ready` | `MENU`（正常）、`LOADING`（调试续档） |
| `MENU` | 否 | 停 | 否 | BOOT、任意状态请求回菜单 | `LOADING`（选图选种完成） |
| `LOADING` | 构建中 | 停（脚本协程运行） | 否 | MENU 选种完成、调试续档 | `PLAYING`（成功）、`MENU`（取消/失败） |
| `PLAYING` | 是 | 运行 | 是 | LOADING 完成、DEAD 重开 | `PAUSED`、`DEAD`、`MENU` |
| `PAUSED` | 是 | 停 | 否 | PLAYING 按暂停 | `PLAYING`（继续）、`MENU` |
| `DEAD` | 是（保留） | 停/尸体展示 | 否 | PLAYING 玩家死亡 | `PLAYING`（respawn）、`MENU` |

| from \ to | BOOT | MENU | LOADING | PLAYING | PAUSED | DEAD |
|---|---|---|---|---|---|---|
| **BOOT** | ✗ | ✓ | ✓（自动续档） | ✗ | ✗ | ✗ |
| **MENU** | ✗ | ✗ | ✓ | ✗ | ✗ | ✗ |
| **LOADING** | ✗ | ✓（取消/失败） | ✗ | ✓（成功且 epoch 匹配） | ✗ | ✗ |
| **PLAYING** | ✗ | ✓ | ✗ | ✗ | ✓ | ✓ |
| **PAUSED** | ✗ | ✓ | ✗ | ✓（继续） | ✗ | ✗ |
| **DEAD** | ✗ | ✓ | ✗ | ✓（respawn） | ✗ | ✗ |

### 2.4 状态转移必须满足的约束

| 编号 | 约束 | 强制方式 |
|---|---|---|
| C1 | 任意时刻只有一个 `state`；不得有并行“半状态” | 单一 `state` 字段 + 转移表 |
| C2 | 只允许走转移表里的边；自转移一律拒绝 | `can_transition(from,to)` |
| C3 | **`LOADING` 不可被 `PAUSED` 打断**；`LOADING` 也不能进 `DEAD` | 表里没有这两条边；额外断言拒绝 |
| C4 | **`DEAD` 只能到 `PLAYING`（respawn）或 `MENU`** | 表限制 + `respawn` payload 校验 |
| C5 | 任意状态到 `MENU` 前必须：先解除暂停、刷写待存盘数据、取消加载协程、释放/重建运行域 | `MENU` 进入钩子 + `Main` 清理 |
| C6 | `MENU` 进入必须幂等；初始 `BOOT→MENU` 与“从游戏回菜单”行为不同，不能互相污染 | `previous == BOOT` 分支；`MENU→MENU` 禁止 |
| C7 | `LOADING→PLAYING` 必须同时满足：世界构建完成（`world_ready`）且捕获的 `load_epoch` 仍有效 | `mark_world_ready()` + `finish_loading(epoch)` |
| C8 | `DEAD→PLAYING` 必须满足：`world_ready == true` 且 payload `respawn=true`，否则拒绝（不能悄悄重建世界） | 实例级 `_validate()` |
| C9 | 死亡只接受第一次触发；3.5 秒展示期内的重复 `died` 信号必须被吞掉 | `state != PLAYING` 早退 + `PlayerDino.is_dead` 实体幂等 |
| C10 | 状态转移同步、非阻塞；任何 `await` 必须放在 Main 协程里，且每个 `await` 之后检查 `load_epoch` | 钩子禁止 `await`；Main 的 `_next_frame(epoch)` |
| C11 | **`get_tree().paused` 只有一个写者：`GameFlow`** | 进入/退出 `PAUSED` 钩子；UI 只请求转移 |
| C12 | UI 不得自己保存流程布尔值；只能读 `flow.state` 或订阅 `state_changed` | `HUD._is_dead` 删除，改为状态查询 |

补充说明：C3/C4 是“表能表达”的静态约束；C7/C8 依赖运行时事实（世界是否构建完成、epoch 是否有效），必须在实例方法里做二次校验。**不要把 `world_ready` 又变成一个散落标志**——它属于 `GameFlow` 内部，只由 `mark_world_ready()` 与进入 `MENU/BOOT` 重置。

### 2.5 旧标志如何迁移，且不破坏“死亡重开不重建世界”

| 旧标志 | 新归属 | 迁移方式 |
|---|---|---|
| `Main.skip_select` | **启动参数**，不是状态 | 过渡期保留为只读兼容开关，`_ready` 时决定 `BOOT→MENU` 还是 `BOOT→LOADING`；最终改为 `--continue` 命令行参数（`OS.get_cmdline_user_args()`），删除静态变量 |
| `Main.is_over` | `GameFlow.State.DEAD` | 死亡处理改 `flow.die()`；重复死亡由 `state != PLAYING` 早退；删除字段 |
| `Main._game_started` | `GameFlow.State.PLAYING` | `_process` 门禁改 `flow.is_playing()`；删除字段 |
| `get_tree().paused` | `GameFlow.State.PAUSED` | `PauseMenu` 只调用 `flow.pause()/resume()`；`GameFlow` 是唯一写者 |
| `HUD._is_dead` | `flow.state == DEAD` | HUD 订阅 `state_changed`，菜单按钮按当前状态分流；删除字段 |
| `PlayerDino.is_dead` | **保留在实体层** | 不做全局化；只作为“该实体不再接受受伤/进食/移动”的局部幂等保护 |

**“死亡重开不重建世界”如何在状态机里表达**：

1. `LOADING→PLAYING` 时 `Main` 在世界构建完成后调用 `flow.mark_world_ready()`，`GameFlow.world_ready = true`。
2. `PLAYING→DEAD` 不清除 `world_ready`，世界资产（地形/水源/植被/自然物/资源点/环境音/蛋）全部保留。
3. `DEAD→PLAYING` 必须携带 `{"respawn": true}`；`_validate()` 要求 `world_ready` 为真，`PLAYING` 进入钩子看到 `respawn` 只调用 `_restart_run()`（只重建运行期节点），**绝不走 `LOADING`**。
4. 只有 `→MENU` / `→BOOT` 才把 `world_ready=false`，随后 `reload_current_scene()` 整场景重建；这是产品的“真的回主菜单”，不是死亡重开。

这样，“不重建世界”从一条注释/一个手工 `_game_started` 变成状态机可校验的契约：**如果谁试图在 `world_ready=false` 时从 `DEAD` 回 `PLAYING`，转移会被拒绝，而不是默默把玩家丢进虚空。**

### 2.6 `GameFlow.gd` 骨架（可运行）

建议路径：`scripts/core/GameFlow.gd`，`Main` 持有，**不注册 autoload**。

```gdscript
class_name GameFlow
extends Node
## 六态游戏流程控制器：BOOT / MENU / LOADING / PLAYING / PAUSED / DEAD
## 职责边界：
## - 只做“阶段合法性 + 暂停唯一写者 + 异步加载令牌”
## - 不做世界构建、不碰存档、不直接生成节点（由 Main 在状态进入信号里编排）
## - 禁止在状态信号回调里同步再次 transition；需要链式转移时用 call_deferred

enum State { BOOT, MENU, LOADING, PLAYING, PAUSED, DEAD }

signal state_changed(from: State, to: State, payload: Dictionary)
signal state_entered(state: State, payload: Dictionary)
signal state_exited(state: State)

const STATE_NAMES: Dictionary = {
	State.BOOT: "BOOT",
	State.MENU: "MENU",
	State.LOADING: "LOADING",
	State.PLAYING: "PLAYING",
	State.PAUSED: "PAUSED",
	State.DEAD: "DEAD",
}

## 允许的边。表里没有的一律拒绝，包括所有自转移。
const ALLOWED: Dictionary = {
	State.BOOT: [State.MENU, State.LOADING],
	State.MENU: [State.LOADING],
	State.LOADING: [State.PLAYING, State.MENU],
	State.PLAYING: [State.PAUSED, State.DEAD, State.MENU],
	State.PAUSED: [State.PLAYING, State.MENU],
	State.DEAD: [State.PLAYING, State.MENU],
}

var state: State = State.BOOT
var previous: State = State.BOOT
var payload: Dictionary = {}
var load_epoch: int = 0       # 每次进入/离开 LOADING 递增，用于废弃过期协程
var world_ready: bool = false # 世界资产是否已完整构建；DEAD→PLAYING 的前置条件
var _transitioning: bool = false


func _ready() -> void:
	# 暂停中仍需响应 UI 的转移请求；信号本身不受 paused 影响，但 ALWAYS 更稳
	process_mode = Node.PROCESS_MODE_ALWAYS


## 纯函数版转移表：供单测 6×6 全覆盖，不依赖节点是否入树
static func can_transition(from: State, to: State) -> bool:
	if from == to:
		return false
	var targets: Array = ALLOWED.get(from, [])
	return targets.has(to)


func can_go(to: State) -> bool:
	return can_transition(state, to)


## 主入口：同步、非阻塞。返回 false 表示被拒绝，当前状态不变。
func transition(to: State, extra: Dictionary = {}) -> bool:
	if _transitioning:
		push_warning("GameFlow: 检测到转移重入，已拒绝 %s" % STATE_NAMES.get(to, "?"))
		return false
	if not can_transition(state, to):
		push_warning("GameFlow: 非法转移 %s -> %s" % [
			STATE_NAMES.get(state, "?"), STATE_NAMES.get(to, "?")])
		return false
	if not _validate(to, extra):
		push_warning("GameFlow: 前置条件不满足 %s -> %s" % [
			STATE_NAMES.get(state, "?"), STATE_NAMES.get(to, "?")])
		return false

	_transitioning = true
	var from: State = state

	_exit_hook(from)
	state_exited.emit(from)

	previous = from
	state = to
	payload = extra.duplicate(true)

	if to == State.BOOT or to == State.MENU:
		world_ready = false
	if to == State.LOADING:
		load_epoch += 1
	elif from == State.LOADING:
		load_epoch += 1

	_enter_hook(to, payload)
	state_changed.emit(from, to, payload)
	state_entered.emit(to, payload)

	_transitioning = false
	return true


## 运行时前置条件：表表达不了的部分
func _validate(to: State, extra: Dictionary) -> bool:
	# LOADING 只有世界构建完成才允许进 PLAYING
	if state == State.LOADING and to == State.PLAYING:
		return world_ready
	# DEAD 只能“原地重生”，不允许借机重建世界
	if state == State.DEAD and to == State.PLAYING:
		return world_ready and bool(extra.get("respawn", false))
	return true


## 每状态进入/退出钩子：只放“状态自身必须做的副作用”，禁止 await
func _enter_hook(to: State, _p: Dictionary) -> void:
	if to == State.PAUSED and is_inside_tree():
		get_tree().paused = true


func _exit_hook(from: State) -> void:
	# 唯一写者：离开 PAUSED 一定解除暂停（包括直接回 MENU）
	if from == State.PAUSED and is_inside_tree():
		get_tree().paused = false


# ================= 语义化入口（Main / UI 只用这些，不直接拼枚举） =================
func begin_loading(extra: Dictionary = {}) -> bool:
	return transition(State.LOADING, extra)


## 世界构建完成后由 Main 调用；之后才允许 LOADING→PLAYING
func mark_world_ready() -> void:
	world_ready = true


## 带 epoch 的加载完成：过期协程不能把状态推进到 PLAYING
func finish_loading(epoch: int) -> bool:
	if state != State.LOADING or epoch != load_epoch or not world_ready:
		return false
	return transition(State.PLAYING, {"source": "loading"})


func pause() -> bool:
	return transition(State.PAUSED)


func resume() -> bool:
	return transition(State.PLAYING, {"source": "resume"})


func die() -> bool:
	return transition(State.DEAD)


func respawn() -> bool:
	return transition(State.PLAYING, {"respawn": true})


func to_menu() -> bool:
	return transition(State.MENU)


# ================= 只读查询（替代散落布尔） =================
func is_playing() -> bool:
	return state == State.PLAYING


func is_dead() -> bool:
	return state == State.DEAD


func is_paused() -> bool:
	return state == State.PAUSED


func is_loading() -> bool:
	return state == State.LOADING


func is_in_run() -> bool:
	return state == State.PLAYING or state == State.PAUSED or state == State.DEAD


## 仅供测试/场景重置使用；正常流程不需要
func reset() -> void:
	state = State.BOOT
	previous = State.BOOT
	payload.clear()
	world_ready = false
	load_epoch += 1
	if is_inside_tree():
		get_tree().paused = false
```

**实现要点说明**：

- `state_exited` 发出时 `state` 仍是旧值；`state_changed/state_entered` 发出时 `state` 已是新值。订阅者若依赖 `flow.state`，应优先用 `state_changed`。
- `_transitioning` 防止信号回调里同步嵌套转移。`Main` 的进入钩子如果必须链式转移（例如加载失败直接回 MENU），用 `call_deferred`。
- `load_epoch` 在进入和离开 `LOADING` 时各加一次：进入时建立新令牌，离开时让旧令牌永久失效。`finish_loading(epoch)` 用捕获值比较。
- `world_ready` 只在 `LOADING→PLAYING` 前由 `Main` 明确标记，只有 `BOOT/MENU` 清除。这样“死亡重开不重建世界”成为状态机的硬约束。

### 2.7 `Main` 如何对齐现有 `_start_game` / `_restart_run` / `_on_menu`

以下是**改动骨架**（保留现有函数体，只改入口与门禁；`# …` 表示原代码原样保留）。

```gdscript
# scripts/game/Main.gd
var flow: GameFlow
var profile: PlayerProfile
var save_repo: SaveRepository

func _ready() -> void:
	# …现有子系统装配（day_night / score_keeper / world_builder / director / 环境音）…
	save_repo = SaveRepository.shared()
	var loaded := save_repo.load_main()
	profile = loaded.profile

	flow = GameFlow.new()
	flow.name = "GameFlow"
	add_child(flow)
	flow.state_entered.connect(_on_flow_state_entered)

	if _auto_continue_requested():
		_map_def = Maps.by_id(profile.map_id)
		day_night.set_map_def(_map_def)
		director.set_map_def(_map_def)
		flow.begin_loading({"species_id": profile.species_id, "is_continue": true})
	else:
		flow.transition(GameFlow.State.MENU)


func _auto_continue_requested() -> bool:
	# 过渡期可继续读 static skip_select；最终改为命令行参数
	return "--continue" in OS.get_cmdline_user_args()


## 所有“进入某状态后要做什么”集中在这里；不要在这些回调里同步二次 transition
func _on_flow_state_entered(s: GameFlow.State, p: Dictionary) -> void:
	match s:
		GameFlow.State.MENU:
			_enter_menu()
		GameFlow.State.LOADING:
			_run_loading(p)
		GameFlow.State.PLAYING:
			if bool(p.get("respawn", false)):
				_restart_run()
			else:
				# 首次进局：世界已就绪，挂提示与引导
				hud.show_hint("管理好饥饿/口渴/体力。靠近湖泊按 E 或饮水键喝水，吃对的食物会成长。")
				hud.show_help()
				add_child(TutorialGuide.new())
		GameFlow.State.DEAD:
			_run_death_sequence()


## 原 _start_game 改成“LOADING 协程”，每个 await 后检查 epoch
func _run_loading(p: Dictionary) -> void:
	var epoch: int = flow.load_epoch
	var species_id: String = str(p.get("species_id", profile.species_id))
	var is_continue: bool = bool(p.get("is_continue", true))

	if not is_continue:
		profile.reset_for_new_run(species_id, _map_def.id)
		save_repo.save_profile(profile, SaveRepository.SaveReason.START)

	score_keeper.reset()
	loading_screen = LoadingScreenScene.instantiate() as LoadingScreen
	dynamic.add_child(loading_screen)
	_set_loading(0.0, "正在准备资源…")

	var ok: bool = await _next_frame(epoch)
	if not ok:
		return
	await _preload_world_assets(epoch)  # 内部每个 await 后同样检查 epoch
	if epoch != flow.load_epoch:
		return

	# …原 _start_game 中地形/水源/植被/自然物/资源点/HUD/玩家/生态/随机事件/触屏…
	# 每两个阶段之间用：if not await _next_frame(epoch): return

	flow.mark_world_ready()
	await loading_screen.fade_out()
	if epoch != flow.load_epoch:
		return
	loading_screen.queue_free()
	loading_screen = null
	flow.finish_loading(epoch)


func _next_frame(epoch: int) -> bool:
	await get_tree().process_frame
	return epoch == flow.load_epoch


func _on_species_selected(species_id: String, is_continue: bool) -> void:
	if species_select != null:
		species_select.queue_free()
		species_select = null
	flow.begin_loading({
		"species_id": species_id,
		"is_continue": is_continue,
		"map_id": _map_def.id,
	})


func _on_player_died() -> void:
	# 只接受 PLAYING 中的第一次死亡；重复信号由状态机拒绝
	flow.die()


func _run_death_sequence() -> void:
	if player == null or not is_instance_valid(player):
		return
	# 唯一写入者：Main 在 DEAD 进入时一次性写完整快照
	profile.growth_stage = player.growth_stage
	profile.generation = player.generation + 1
	profile.best_time = maxi(profile.best_time, int(score_keeper.survival_time))
	profile.best_kills = maxi(profile.best_kills, score_keeper.kill_count)
	save_repo.save_profile(profile, SaveRepository.SaveReason.DEATH)

	var best := "最佳存活 %d 秒 / 最多击杀 %d" % [profile.best_time, profile.best_kills]
	hud.show_death("你被猎杀了！\n第 %d 代 · 存活 %d 秒 · 击杀 %d\n成长已保留，下一局继续变强\n%s" % [
		player.generation, int(score_keeper.survival_time), score_keeper.kill_count, best])

	await get_tree().create_timer(3.5).timeout
	if flow.state != GameFlow.State.DEAD:
		return   # 玩家期间点了回主菜单，放弃重生
	flow.respawn()


## 原 _restart_run：删除 is_over/_game_started 操作，改为读内存 profile；只在 respawn 分支调用
func _restart_run() -> void:
	# 1) …原 11 项释放清单不变…
	score_keeper.reset_all()

	# 2) 从内存快照读，不再 load_save()
	var stage: int = profile.growth_stage
	var gen: int = profile.generation
	var egg := _find_player_egg()
	var spawn_pos: Vector3 = PLAYER_SPAWN
	if egg != null:
		spawn_pos = egg.global_position
		stage = maxi(stage, egg.growth_stage_snapshot)
		if stage != profile.growth_stage:
			profile.growth_stage = stage
			save_repo.save_profile(profile, SaveRepository.SaveReason.EVOLUTION)

	# 3) …原旧蛋清理、HUD/玩家/生态/事件/触屏重建…
	_spawn_hud()  # 内部：hud.flow = flow; dynamic.add_child(hud)
	_spawn_player(profile.species_id, stage, gen, spawn_pos)


func _spawn_hud() -> void:
	hud = HUDScene.instantiate() as HUD
	hud.flow = flow                 # 必须在 add_child 前注入，HUD._ready 才能订阅
	dynamic.add_child(hud)
	hud.menu_pressed.connect(_on_menu)


func _on_menu() -> void:
	flow.to_menu()


func _enter_menu() -> void:
	# 初次 BOOT→MENU：显示选图，绝不 reload（否则无限重载）
	if flow.previous == GameFlow.State.BOOT:
		_show_map_select()
		return
	# 从游戏/暂停/死亡/加载取消回菜单：先落盘再整场景重载
	save_repo.save_profile(profile, SaveRepository.SaveReason.MENU)
	NatureBatch.clear_cache()
	get_tree().call_deferred("reload_current_scene")


func _process(delta: float) -> void:
	if flow == null:
		return
	if flow.state == GameFlow.State.DEAD:
		return   # 死亡展示期与旧 is_over 语义一致：计分/生态/昼夜全部冻结
	if flow.state == GameFlow.State.PLAYING:
		# …原计分 / 生态补员 / 技能冷却…
		pass
	day_night.update(delta)   # 菜单/加载背景仍保持昼夜，与原行为一致


func _exit_tree() -> void:
	NatureBatch.clear_cache()
	var tree := get_tree()
	if tree != null and tree.paused:
		tree.paused = false   # 防止 reload 时把 paused=true 带进新场景
```

**与现有路径逐项对齐**：

| 现有函数 | 新位置 |
|---|---|
| `_ready` 的 `skip_select` 分支 | `_ready` 的 `BOOT→MENU/LOADING` 选择 |
| `_on_map_selected` / `_show_species_select` | 保持在 `MENU` 子视图内，不改状态 |
| `_on_species_selected` | `flow.begin_loading(payload)` |
| `_start_game` | 改名为 `_run_loading(p)`，末尾 `mark_world_ready + finish_loading(epoch)` |
| `_on_player_died` | `flow.die()`；实际存档/UI/延时在 `_run_death_sequence` |
| `_restart_run` | `DEAD→PLAYING(respawn)` 的进入钩子；不再读写流程标志 |
| `_on_menu` | `flow.to_menu()`；清理在 `_enter_menu` |
| `_process` 的 `is_over` / `_game_started` | `flow.state == DEAD` / `flow.is_playing()` |

**过渡期兼容**：第一版可以保留 `static var skip_select`，只在 `_ready` 读取一次并置 false，映射为 `BOOT→LOADING`；等全链路验收通过后再删。这样既不改冒烟脚本，也不让静态标志继续参与运行期判断。

### 2.8 状态机与 UI 的同步方式

**推荐：事件订阅 + 绑定时重放当前状态；轮询只用于每帧门禁。**

| 方式 | 适用 | 本项目做法 |
|---|---|---|
| 订阅 `state_changed` | 离散 UI（暂停菜单显隐、死亡屏、按钮分流、触控输入复位） | **主方案**。HUD、PauseMenu、TouchControls 都订阅 |
| 绑定时重放 | 节点在某个状态中被新建（HUD 在 LOADING 末尾或 PLAYING respawn 中创建） | `bind` 后立即 `_apply_flow_state(flow.state)`，否则会漏掉创建前已发生的那次转移 |
| 轮询 `flow.state` | `_process` 的每帧门禁、`_process` 里读计分是否运行 | 只允许这种低频枚举比较；禁止 UI 用轮询决定显隐 |
| 本地布尔副本 | 任何场景 | **禁止**。`HUD._is_dead`、`Main.is_over`、`Main._game_started` 全部删除 |

官方文档明确：暂停时 `_process/_physics_process/_input` 可能不再调用，但**信号仍然会送达并执行连接函数**（见 `pausing_games.html`）。因此暂停菜单可以安全地靠 `state_changed` 显隐；但**不要依赖暂停中的 tween/animation 完成回调来推进状态**。

HUD 改动要点：

```gdscript
# scripts/ui/HUD.gd
var flow: GameFlow

func _ready() -> void:
	# …原有 UI 构建…
	_pause_menu = PauseMenu.new()
	_pause_menu.flow = flow
	add_child(_pause_menu)
	if flow != null:
		flow.state_changed.connect(_on_flow_state_changed)
		_apply_flow_state(flow.state)   # 绑定即重放，防止创建前已进 PAUSED/PLAYING

func _on_flow_state_changed(_from: GameFlow.State, to: GameFlow.State, _p: Dictionary) -> void:
	_apply_flow_state(to)

func _apply_flow_state(s: GameFlow.State) -> void:
	if _pause_menu == null:
		return
	if s == GameFlow.State.PAUSED:
		_pause_menu.open_ui()
	else:
		_pause_menu.close_ui()

func _on_menu_button() -> void:
	if flow == null:
		return
	if flow.state == GameFlow.State.DEAD:
		flow.to_menu()
	elif flow.state == GameFlow.State.PLAYING:
		flow.pause()
```

`PauseMenu` 改动要点：

```gdscript
# scripts/ui/PauseMenu.gd
var flow: GameFlow

func open_ui() -> void:   # 原 open() 去掉 get_tree().paused = true
	_show_main()
	if _ach_button != null:
		_ach_button.text = _achievements_button_text()
	visible = true

func close_ui() -> void:  # 原 close() 去掉 get_tree().paused = false
	visible = false

func _on_continue_pressed() -> void:
	if flow != null:
		flow.resume()

func _on_exit_pressed() -> void:
	# 不再手工 unpause；GameFlow 退出 PAUSED 时会解除暂停
	if flow != null:
		flow.to_menu()
	else:
		exit_to_menu.emit()   # 兼容 standalone 预览/测试场景
```

注意：同时把 `_build_ui` 中「继续」按钮的 handler 从 `close` 改为 `_on_continue_pressed`；「回到主菜单」仍连 `_on_exit_pressed`。这样 UI 只“请求转移”，显隐由 HUD 的 `state_changed` 统一处理，不会出现“按钮自己 unpause 但状态机仍以为在 PAUSED”的分叉。

`TouchControls` 可选优化：现有 `_process` 轮询 `get_tree().paused` 的上升沿来复位输入（`TouchControls.gd:63-71`）。改造后可订阅 `flow.state_changed`，在 `to == PAUSED` 时调用 `_reset_input_state()`，去掉轮询与 `_was_paused`；过渡期保留现有实现也不影响正确性。

### 2.9 暂停时谁还活着：PROCESS_MODE 矩阵

| 节点 / 系统 | 建议模式 | 理由 |
|---|---|---|
| `GameFlow` | `ALWAYS` | 暂停中仍要接收“继续/回菜单”请求并完成转移；自身不做物理 |
| `Main` | `PAUSABLE`（默认 Inherit） | 暂停时 `_process` 停，正好冻结计分/生态/昼夜 |
| `LoadingScreen` | `ALWAYS`（现状） | 即使暂停残留也能显示/淡出；加载期间拦截触摸 |
| `HUD` | `PAUSABLE` | 显隐由信号驱动；暂停时横幅 tween 冻结是期望行为 |
| `PauseMenu` | `WHEN_PAUSED`（现状） | 暂停时可点击；非暂停时不可见 |
| `TouchControls` 根 | `ALWAYS`（现状） | 保留暂停沿输入复位；子控件 `PAUSABLE` 不再响应触摸 |
| `PlayerDino` / `AIDino` / 尸体 / 蛋 / 植被 / 资源点 | `PAUSABLE` | 世界实体应停 |
| `DayNightCycle` / `ScoreKeeper` / `EcosystemDirector` / `RandomEvents` | `PAUSABLE` | 暂停冻结世界时间、计分、补员、事件 |
| `DebugOverlay` | `ALWAYS`（现状） | 暂停时仍可观察性能 |
| `GameState` / `AudioManager` / `Achievements` autoload | 默认 `INHERIT` | 暂停时音频/计时随树停；若希望环境音继续，单独给 AudioStreamPlayer 设 `ALWAYS` |

**重要物理事实**：`SceneTree.paused = true` 会全局停止 2D/3D 物理与碰撞检测，**与节点 `process_mode` 无关**；`ALWAYS` 只保证回调继续，物理仍停（官方 `SceneTree.paused` 与 `pausing_games` 文档）。所以不要给玩家/AI 设 `ALWAYS` 指望暂停时还能移动。

### 2.10 GameFlow 测试

| 层级 | 用例 | 断言 |
|---|---|---|
| 纯表 | 6×6=36 个 `(from,to)` 全枚举 | 合法边与 2.3 矩阵逐项一致；自转移全 false |
| 纯表 | `LOADING→PAUSED`、`LOADING→DEAD`、`PAUSED→DEAD`、`DEAD→PAUSED`、`MENU→PLAYING` | 全部 false |
| 实例 | 非法转移后 `state` 不变、`state_changed` 未发出 | 状态与信号计数不变 |
| 实例 | `PAUSED` 进入/退出 | `get_tree().paused` 分别为 true/false；退出 PAUSED 直接到 MENU 也解除暂停 |
| 实例 | `world_ready=false` 时 `LOADING→PLAYING`、`DEAD→PLAYING` | 均拒绝 |
| 实例 | 进入/离开 LOADING | `load_epoch` 递增；旧 epoch 的 `finish_loading` 返回 false |
| 信号顺序 | 一次合法转移 | 顺序为 `state_exited(旧)` → `state_changed(旧,新)` → `state_entered(新)`；`state_exited` 时读 `state` 仍是旧值 |
| 集成 | 选图→选种→加载→游玩→暂停→继续→死亡→重生→回菜单 | headless 16s 无脚本错误；状态日志顺序完整；`reload` 后新场景 `paused=false` |

测试放置：纯表与实例用例进 `tests/run_tests.gd`（`extends SceneTree`，已有 `check()` 与 `quit()` 机制）；实例用例把 `GameFlow.new()` 挂到 `root`，用完 `queue_free()`，并在结束前强制 `paused=false`。

---

## 3. 问题二：存档架构与版本迁移

### 3.1 目标分层

```
┌──────────────────────────────────────────────────────────┐
│ 调用方（Main / SpeciesSelect / HUD）                      │
│ 只读 PlayerProfile；只有 Main 可以提交修改                 │
└───────────────┬──────────────────────────────────────────┘
                │ load / save(profile, reason)
┌───────────────▼──────────────────────────────────────────┐
│ SaveRepository（唯一 IO 入口）                            │
│ - 路径/槽位、原子写、备份轮换、校验和、损坏隔离            │
│ - 调用 SaveMigrator，把任意旧版 Dictionary 升到当前版      │
│ - 未来版本：隔离 + read_only，绝不覆盖                     │
└───────────────┬──────────────────────────────────────────┘
                │ Dictionary
┌───────────────▼──────────────────────────────────────────┐
│ SaveMigrator（纯函数迁移链 v0→v1→…）                      │
└───────────────┬──────────────────────────────────────────┘
                │ dict ↔ typed snapshot
┌───────────────▼──────────────────────────────────────────┐
│ PlayerProfile（typed Resource，内存模型）                 │
│ 强类型字段 + 默认值 + 范围钳制 + extra_fields 未知键保留   │
└──────────────────────────────────────────────────────────┘
```

职责一句话：

- `PlayerProfile`：**内存里的唯一形状**，所有游戏代码读它，不读字典。
- `SaveMigrator`：**只做数据升级**，纯函数、无 IO、无副作用，易单测。
- `SaveRepository`：**唯一碰文件的地方**，负责“写得进去、读得出来、坏了能退”。
- 调用方：**只读 profile**；写只有 `Main`。

### 3.2 存储格式决策：JSON vs `.tres/.res` vs ConfigFile

| 维度 | JSON（推荐） | 自定义 `Resource` + `ResourceSaver` | `ConfigFile` |
|---|---|---|---|
| 类型安全 | 磁盘无类型，需 mapper；内存有 typed `PlayerProfile` | 强类型、引擎原生类型 | Variant 保类型，但只适合扁平设置 |
| 迁移/版本链 | 字典操作最直接，未知键易保留 | 结构绑脚本类；改类名/字段/路径会破坏旧档，迁移需额外包装 | 分节键值，嵌套结构难表达 |
| 可读/可 diff | 是 | `.tres` 可读但冗长；`.res` 二进制不可读 | 是 |
| 安全 | **不执行代码**（`JSON.parse` 只产生 Variant） | **加载资源可能执行内嵌脚本**，官方与 GDQuest 均警告勿加载不可信资源 | 不执行代码 |
| 原子写/备份 | 自行实现（本报告方案） | 需自行实现；`ResourceSaver` 不保证原子 | 需自行实现 |
| 适合本项目 | ✅ 单机、小档、需要迁移与未来云同步 | 可作为“内存模型”，不作为磁盘格式 | ❌ 存档不是设置 |

**结论**：磁盘用 **JSON**，内存用 **typed `PlayerProfile`（`extends Resource`）**，但不使用 `ResourceSaver/ResourceLoader` 读写存档。这样既有强类型与默认值，又避免资源加载的代码执行面、脚本绑定和二进制迁移难题。

### 3.3 目录布局与旧档导入

```
user://save.json                              # 旧档：只读导入源，成功后保留不删
user://saves/
  .legacy_imported                            # 标记：旧档只导入一次，防止删档后“复活”
  slot_main/
    profile.json                              # 当前槽位
    profile.json.tmp                          # 写入中间态（正常不应残留）
    profile.json.bak                          # 上一份有效档
    profile.json.bak.1                        # 再上一份
    profile.json.corrupt-<unix>               # 损坏隔离
    profile.json.future-v<N>-<unix>           # 未来版本隔离
  slot_2/…                                    # 预留多槽位
  active_slot.txt                             # 预留：当前槽位 id
```

- 当前只启用 `slot_main`，但**路径从第一天就按槽位参数化**，后续加槽位不需要搬文件。
- 首次启动若 `user://saves/slot_main/profile.json` 不存在且 `user://save.json` 存在：读旧档 → 迁移 → 写入新路径 → 旧文件**保留**（便于回滚）。
- 导入成功后写 `.legacy_imported` 标记：否则玩家主动删掉新档后，下次启动又会从旧档“复活”，这是迁移期特有的坑。
- 旧档损坏/未来版本：不导入，保留原文件；新路径保持缺失，界面按“无档”处理。
- 不把 `user://save.json` 直接改名为新路径，避免导入失败后两边都没有。

### 3.4 Schema 常量与 `PlayerProfile`

建议路径：`scripts/data/PlayerProfile.gd`。

```gdscript
class_name PlayerProfile
extends Resource
## 存档的内存模型：强类型、默认值、范围钳制。
## 注意：不使用 ResourceSaver 落盘；磁盘格式由 SaveRepository 负责（JSON）。
## extra_fields 保存“当前版本不认识的顶层键”，确保旧客户端不会把未来字段写丢。

@export var species_id: String = DinoSpecies.ID_RAPTOR
@export var growth_stage: int = 0
@export var generation: int = 1
@export var map_id: String = Maps.DEFAULT_MAP_ID
@export var best_time: int = 0
@export var best_kills: int = 0
@export var play_time_seconds: float = 0.0
@export var revision: int = 0          # 每次写盘尝试 +1；失败不落盘，内存值可能领先
@export var updated_at: int = 0        # Unix 秒；未来云同步“谁更新”判定用
@export var slot_id: String = "main"   # 多槽位扩展点

## 当前版本认识的键；其余进 extra_fields
const KNOWN_KEYS: Array[String] = [
	"save_version", "checksum",
	"species_id", "growth_stage", "generation", "map_id",
	"best_time", "best_kills", "play_time_seconds",
	"revision", "updated_at", "slot_id",
]

var extra_fields: Dictionary = {}


## 新开一局：只重置“本局身份”，保留生涯最佳记录
func reset_for_new_run(p_species_id: String, p_map_id: String) -> void:
	species_id = p_species_id
	map_id = p_map_id
	growth_stage = 0
	generation = 1
	play_time_seconds = 0.0


## 转成磁盘字典；save_version / checksum 由 SaveRepository 统一添加
func to_dict() -> Dictionary:
	var d: Dictionary = extra_fields.duplicate(true)
	d["species_id"] = species_id
	d["growth_stage"] = growth_stage
	d["generation"] = generation
	d["map_id"] = map_id
	d["best_time"] = best_time
	d["best_kills"] = best_kills
	d["play_time_seconds"] = play_time_seconds
	d["revision"] = revision
	d["updated_at"] = updated_at
	d["slot_id"] = slot_id
	return d


## 从“已迁移到当前版”的字典构造；所有字段做类型转换 + 范围钳制
static func from_dict(d: Dictionary, p_slot_id: String) -> PlayerProfile:
	var p := PlayerProfile.new()
	p.slot_id = p_slot_id

	p.species_id = str(d.get("species_id", DinoSpecies.ID_RAPTOR))
	if DinoSpecies.by_id(p.species_id) == null:
		p.species_id = DinoSpecies.ID_RAPTOR

	p.growth_stage = clampi(int(d.get("growth_stage", 0)), 0, DinoSpecies.MAX_STAGE)
	p.generation = maxi(int(d.get("generation", 1)), 1)
	p.map_id = Maps.by_id(str(d.get("map_id", Maps.DEFAULT_MAP_ID))).id
	p.best_time = maxi(int(d.get("best_time", 0)), 0)
	p.best_kills = maxi(int(d.get("best_kills", 0)), 0)
	p.play_time_seconds = maxf(float(d.get("play_time_seconds", 0.0)), 0.0)
	p.revision = maxi(int(d.get("revision", 0)), 0)
	p.updated_at = maxi(int(d.get("updated_at", 0)), 0)

	for k: Variant in d.keys():
		var key := String(k)
		if not KNOWN_KEYS.has(key):
			p.extra_fields[key] = d[k]
	return p
```

**字段规则表**：

| 键 | 类型 | 默认 | 校验/钳制 | 迁移注意 |
|---|---|---|---|---|
| `save_version` | int | 0（旧档缺省） | `int()`；`> CURRENT` 走未来版本分支 | 版本号只在 Repository/Migrator 维护 |
| `checksum` | String | 无 | 有则校验；旧档无则跳过 | 不参与 `PlayerProfile.to_dict()` |
| `species_id` | String | `raptor` | 必须命中 `DinoSpecies.by_id` | 未知物种回退迅猛龙 |
| `growth_stage` | int | 0 | `0..DinoSpecies.MAX_STAGE` | JSON 数字是 float，必须 `int()` |
| `generation` | int | 1 | `>=1` | 同上 |
| `map_id` | String | `forest` | `Maps.by_id` 总返回有效 def | 未知地图回退默认 |
| `best_time` | int | 0 | `>=0` | 只增不减（Main 用 `maxi`） |
| `best_kills` | int | 0 | `>=0` | 同上 |
| `play_time_seconds` | float | 0.0 | `>=0` | v2 起启用的示例字段 |
| `revision` | int | 0 | `>=0` | 每次成功保存 +1；云冲突用 |
| `updated_at` | int | 0 | `>=0` | Unix 秒；云冲突用 |
| `slot_id` | String | `"main"` | 合法文件名 | 多槽位扩展点 |
| 未知键 | 任意 | 保留 | 原样进 `extra_fields` | 防旧版覆盖未来字段 |

### 3.5 `SaveRepository` 骨架（唯一 IO 入口）

建议路径：`scripts/data/SaveRepository.gd`。

```gdscript
class_name SaveRepository
extends RefCounted
## 唯一存档 IO 入口：原子写、备份轮换、校验和、损坏隔离、未来版本保护、迁移链。
## 提供 shared() 仅为过渡期兼容门面；正式调用方由 Main 持有一个实例。

const CURRENT_VERSION: int = 1
const ROOT_DIR: String = "user://saves"
const LEGACY_PATH: String = "user://save.json"
const PROFILE_FILE: String = "profile.json"
const CHECKSUM_KEY: String = "checksum"

enum LoadStatus { OK, MISSING, MIGRATED, RECOVERED, FUTURE_VERSION, CORRUPT }
enum SaveReason { START, EVOLUTION, DEATH, MANUAL, AUTOSAVE, APP_PAUSE, MENU }

class LoadResult:
	var profile: PlayerProfile = null
	var status: int = 0          # LoadStatus
	var from_version: int = 0
	var has_progress: bool = false
	var read_only: bool = false  # 未来版本档：本次会话禁止写入
	var message: String = ""

static var _shared: SaveRepository = null
var _root: String
var _import_legacy: bool = true
var _last_error: String = ""


func _init(p_root: String = ROOT_DIR, p_import_legacy: bool = true) -> void:
	_root = p_root
	_import_legacy = p_import_legacy


static func shared() -> SaveRepository:
	if _shared == null:
		_shared = SaveRepository.new()
	return _shared


func get_last_error() -> String:
	return _last_error


func slot_dir(p_slot_id: String) -> String:
	return "%s/slot_%s" % [_root, p_slot_id]


func profile_path(p_slot_id: String) -> String:
	return slot_dir(p_slot_id).path_join(PROFILE_FILE)


# ================= 读 =================

func load_main() -> LoadResult:
	return load_slot("main")


func load_slot(p_slot_id: String) -> LoadResult:
	var path := profile_path(p_slot_id)
	if not FileAccess.file_exists(path):
		if _import_legacy:
			var legacy := _try_import_legacy(p_slot_id)
			if legacy != null:
				return legacy
		var missing := LoadResult.new()
		missing.status = LoadStatus.MISSING
		missing.profile = PlayerProfile.new()
		missing.profile.slot_id = p_slot_id
		return missing

	var parsed := _read_json(path)
	if parsed.is_empty():
		return _recover(path, p_slot_id, "JSON 解析失败")

	var version := int(parsed.get("save_version", 0))

	# 未来版本：隔离原文件，返回默认档 + read_only；绝不覆盖
	if version > CURRENT_VERSION:
		_quarantine(path, "future-v%d" % version)
		var future := LoadResult.new()
		future.status = LoadStatus.FUTURE_VERSION
		future.from_version = version
		future.read_only = true
		future.message = "存档来自更新版本（v%d），已隔离；本次会话只读" % version
		future.profile = PlayerProfile.new()
		future.profile.slot_id = p_slot_id
		return future

	if not _checksum_ok(parsed):
		return _recover(path, p_slot_id, "校验和不匹配")

	var migrated := SaveMigrator.migrate(parsed)
	if migrated.is_empty():
		return _recover(path, p_slot_id, "迁移失败")

	var res := LoadResult.new()
	res.from_version = version
	res.status = LoadStatus.MIGRATED if version < CURRENT_VERSION else LoadStatus.OK
	res.has_progress = migrated.has("species_id") and migrated.has("growth_stage")
	res.profile = PlayerProfile.from_dict(migrated, p_slot_id)
	return res


func has_progress(p_slot_id: String = "main") -> bool:
	return load_slot(p_slot_id).has_progress


# ================= 写 =================

## 调用方只提交完整快照；Repository 负责版本、校验和、原子替换、备份
func save_profile(profile: PlayerProfile, reason: int) -> Error:
	if profile == null:
		return ERR_INVALID_PARAMETER

	var mk := DirAccess.make_dir_recursive_absolute(slot_dir(profile.slot_id))
	if mk != OK and mk != ERR_ALREADY_EXISTS:
		_last_error = "无法创建存档目录：%s" % error_string(mk)
		return mk

	profile.revision += 1
	profile.updated_at = int(Time.get_unix_time_from_system())

	var d := profile.to_dict()
	d["save_version"] = CURRENT_VERSION
	d[CHECKSUM_KEY] = _canonical(d).sha256_text()
	var text := JSON.stringify(d, "\t", true)

	var err := _atomic_write(profile_path(profile.slot_id), text)
	if err != OK:
		_last_error = "保存失败（reason=%d）：%s" % [reason, error_string(err)]
	return err


## 原子写：tmp → 回读校验 → 轮换备份 → rename 覆盖
func _atomic_write(path: String, text: String) -> Error:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		_last_error = "无法打开临时文件：%s" % error_string(FileAccess.get_open_error())
		return FileAccess.get_open_error()
	f.store_string(text)
	f.flush()
	f.close()

	# 回读校验：确认落盘内容与内存一致（防截断/半写）
	var check := FileAccess.open(tmp, FileAccess.READ)
	if check == null:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CANT_READ
	var written := check.get_as_text()
	check.close()
	if written != text:
		DirAccess.remove_absolute(tmp)
		return ERR_FILE_CORRUPT

	if FileAccess.file_exists(path):
		var bak_err := _rotate_backup(path)
		if bak_err != OK:
			DirAccess.remove_absolute(tmp)
			_last_error = "备份失败，已放弃写入：%s" % error_string(bak_err)
			return bak_err

	# 官方文档：目标存在且非写保护时会被覆盖
	var err := DirAccess.rename_absolute(tmp, path)
	if err != OK:
		DirAccess.remove_absolute(tmp)
	return err


func _rotate_backup(path: String) -> Error:
	var bak := path + ".bak"
	var bak1 := path + ".bak.1"
	if FileAccess.file_exists(bak1):
		var rm := DirAccess.remove_absolute(bak1)
		if rm != OK:
			return rm
	if FileAccess.file_exists(bak):
		var mv := DirAccess.rename_absolute(bak, bak1)
		if mv != OK:
			return mv
	return DirAccess.copy_absolute(path, bak)


# ================= 损坏 / 未来版本 =================

func _recover(path: String, p_slot_id: String, msg: String) -> LoadResult:
	_quarantine(path, "corrupt-%d" % int(Time.get_unix_time_from_system()))

	# 尝试 .bak：只有校验通过、版本不高于当前才接受
	var bak := path + ".bak"
	if FileAccess.file_exists(bak):
		var parsed := _read_json(bak)
		if not parsed.is_empty() and _checksum_ok(parsed):
			var version := int(parsed.get("save_version", 0))
			if version <= CURRENT_VERSION:
				var migrated := SaveMigrator.migrate(parsed)
				if not migrated.is_empty():
					DirAccess.copy_absolute(bak, path)
					var recovered := LoadResult.new()
					recovered.status = LoadStatus.RECOVERED
					recovered.from_version = version
					recovered.has_progress = migrated.has("species_id") and migrated.has("growth_stage")
					recovered.profile = PlayerProfile.from_dict(migrated, p_slot_id)
					recovered.message = msg + "；已从 .bak 恢复"
					return recovered

	var corrupt := LoadResult.new()
	corrupt.status = LoadStatus.CORRUPT
	corrupt.message = msg
	corrupt.profile = PlayerProfile.new()
	corrupt.profile.slot_id = p_slot_id
	return corrupt


func _quarantine(path: String, tag: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var dst := "%s.%s-%d" % [path, tag, int(Time.get_unix_time_from_system())]
	var err := DirAccess.rename_absolute(path, dst)
	if err != OK:
		push_warning("SaveRepository: 隔离失败 %s（%s）" % [dst, error_string(err)])


# ================= 旧档 =================

func _try_import_legacy(p_slot_id: String) -> LoadResult:
	if FileAccess.file_exists(legacy_marker_path()):
		return null   # 已导入过：删掉新档后不允许旧档“复活”
	if not FileAccess.file_exists(LEGACY_PATH):
		return null
	var raw := _read_json(LEGACY_PATH)
	if raw.is_empty():
		return null
	var version := int(raw.get("save_version", 0))
	if version > CURRENT_VERSION:
		return null   # 未来版本旧档不导入、不删除
	var migrated := SaveMigrator.migrate(raw)
	if migrated.is_empty():
		return null

	var res := LoadResult.new()
	res.status = LoadStatus.MIGRATED
	res.from_version = version
	res.has_progress = migrated.has("species_id") and migrated.has("growth_stage")
	res.profile = PlayerProfile.from_dict(migrated, p_slot_id)
	res.message = "已从旧档 user://save.json 导入"
	var err := save_profile(res.profile, SaveReason.START)   # 导入即生成新路径
	if err == OK:
		_mark_legacy_imported()
	return res


func legacy_marker_path() -> String:
	return _root.path_join(".legacy_imported")


func _mark_legacy_imported() -> void:
	DirAccess.make_dir_recursive_absolute(_root)
	var f := FileAccess.open(legacy_marker_path(), FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()


# ================= 工具 =================

func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		_last_error = "JSON 错误：%s（行 %d）" % [json.get_error_message(), json.get_error_line()]
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	return json.data


## 校验和只覆盖“除 checksum 外的全部键”；sort_keys=true 保证键序稳定。
## 关键：JSON 解析后所有数字都变成 float，而写入时部分字段是 int。
## 若直接对字典 JSON 取哈希，"2" 与 "2.0" 会得到不同结果，导致每次重载都误判损坏。
## 因此先做类型归一化：所有数字统一按“整数值/浮点值”编码，再取 SHA-256。
static func _canonical(d: Dictionary) -> String:
	var copy := d.duplicate(true)
	copy.erase(CHECKSUM_KEY)
	return JSON.stringify(_normalize(copy), "", true)


static func _normalize(v: Variant) -> Variant:
	match typeof(v):
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			for k: Variant in (v as Dictionary).keys():
				out[String(k)] = _normalize((v as Dictionary)[k])
			return out
		TYPE_ARRAY:
			var arr: Array = []
			for item: Variant in (v as Array):
				arr.append(_normalize(item))
			return arr
		TYPE_INT, TYPE_FLOAT:
			var f := float(v)
			# 整数值统一写成 n:<整数>，抹平 int/float 的类型差异
			if is_equal_approx(f, roundf(f)):
				return "n:%d" % int(roundf(f))
			return "n:%.6f" % f
		TYPE_STRING, TYPE_STRING_NAME:
			return "s:" + String(v)   # 前缀避免字符串 "n:2" 与数字 2 碰撞
		TYPE_BOOL:
			return "b:%s" % ("true" if bool(v) else "false")
		TYPE_NIL:
			return "z:null"
		_:
			return "x:%s" % str(v)


func _checksum_ok(d: Dictionary) -> bool:
	if not d.has(CHECKSUM_KEY):
		return true   # 旧档没有校验和：允许通过，由迁移链负责
	return String(d[CHECKSUM_KEY]) == _canonical(d).sha256_text()


# ================= 多槽位扩展点（现在不实现 UI） =================

func list_slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(_root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and entry.begins_with("slot_"):
			var slot_id := entry.trim_prefix("slot_")
			var res := load_slot(slot_id)
			out.append({
				"slot_id": slot_id,
				"status": res.status,
				"species_id": res.profile.species_id if res.profile != null else "",
				"growth_stage": res.profile.growth_stage if res.profile != null else 0,
				"generation": res.profile.generation if res.profile != null else 0,
				"updated_at": res.profile.updated_at if res.profile != null else 0,
				"revision": res.profile.revision if res.profile != null else 0,
			})
		entry = dir.get_next()
	dir.list_dir_end()
	return out
```

**校验和的三条实现注意**：

1. **只做完整性，不做防作弊**：它能发现截断、半写、字段被改，但不能阻止玩家修改存档。定位是“坏了能发现并回退”，不是“防篡改”。
2. **必须做数字归一化**：Godot 的 JSON 解析把所有数字读成 `float`，而写入时 `growth_stage/generation/best_*` 是 `int`。若直接哈希原始字典，"2" 与 "2.0" 会产生不同哈希，导致每次重载都误判损坏。`_normalize()` 把整数值统一编码为 `n:<整数>`，浮点保留 6 位，字符串/布尔/null 加类型前缀，避免碰撞。
3. **旧档无 `checksum` 时跳过校验**：先迁移，下一次写入自动补上；不要因为旧档没有校验和而拒绝加载。

### 3.6 版本迁移：链结构、每步函数与规则

建议路径：`scripts/data/SaveMigrator.gd`。

```gdscript
class_name SaveMigrator
extends RefCounted
## 纯函数迁移链：不做 IO、不依赖节点、不修改调用方字典（duplicate 后处理）。
## 规则：
## 1) 只处理“已知键”的语义变化；未知键原样保留
## 2) 每一步只负责 vN → vN+1；缺失步骤 = 失败（fail closed），不猜
## 3) 迁移后的字典必须写回 save_version
## 4) 未来版本不迁移，由 SaveRepository 隔离

const CURRENT_VERSION: int = 1


static func migrate(raw: Dictionary) -> Dictionary:
	var d: Dictionary = raw.duplicate(true)
	var version := int(d.get("save_version", 0))
	if version > CURRENT_VERSION:
		return {}
	while version < CURRENT_VERSION:
		var next: Dictionary = {}
		match version:
			0:
				next = _v0_to_v1(d)
			# 1: next = _v1_to_v2(d)
			# 2: next = _v2_to_v3(d)
			_:
				push_warning("SaveMigrator: 缺少 v%d→v%d 迁移步骤" % [version, version + 1])
				return {}
		if next.is_empty():
			return {}
		d = next
		version += 1
		d["save_version"] = version
	return d


## v0 = 没有 save_version 的早期档：补默认地图，其余原样保留
static func _v0_to_v1(d: Dictionary) -> Dictionary:
	if not d.has("map_id"):
		d["map_id"] = Maps.DEFAULT_MAP_ID
	return d


## 示例：真正升到 v2 时启用（新增字段，缺失补默认；显式落盘，旧档新档同形）
static func _v1_to_v2(d: Dictionary) -> Dictionary:
	if not d.has("play_time_seconds"):
		d["play_time_seconds"] = 0.0
	if not d.has("revision"):
		d["revision"] = 0
	if not d.has("updated_at"):
		d["updated_at"] = 0
	return d


## 示例：真正升到 v3 时启用（结构重命名：扁平记录 → records 子对象）
static func _v2_to_v3(d: Dictionary) -> Dictionary:
	var records: Dictionary = {}
	if d.has("best_time"):
		records["best_time"] = int(d["best_time"])
		d.erase("best_time")
	if d.has("best_kills"):
		records["best_kills"] = int(d["best_kills"])
		d.erase("best_kills")
	if not records.is_empty():
		d["records"] = records
	return d
```

**迁移规则表**：

| 情况 | 处理 | 理由 |
|---|---|---|
| 缺 `save_version` | 视为 v0，走 `_v0_to_v1` | 早期档确实没有版本键 |
| 旧版 < 当前 | 逐级迁移，每级只做一件事 | 单步可测；失败可定位到具体版本 |
| 缺字段 | 迁移或 `PlayerProfile.from_dict` 补默认 | 加法字段可安全默认；语义变化必须迁移 |
| 多字段 | **保留**（`extra_fields`） | 防旧客户端覆盖新客户端字段 |
| 未知枚举/ID（物种、地图） | 回退默认并记录 warning | 不因数据缺失崩溃 |
| 未来版本 `>CURRENT` | 隔离原文件 + 返回默认档 + `read_only` | 绝不覆盖；玩家换回新版本仍能读到原档 |
| 损坏 JSON / 校验和不符 | 隔离 + 尝试 `.bak` | 保留现场，优先恢复上一份有效档 |
| 迁移链缺步骤 | 返回空字典 → 按损坏处理 | 宁可回退备份，不做猜测性迁移 |

**为什么版本号不能只靠“缺字段补默认”**：补默认能处理“新增可选字段”，但处理不了“字段含义变了”“字段拆成子对象”“枚举值重编号”。这些必须在版本号上体现；否则新旧代码会以不同语义读同一个值，属于静默数据损坏。

### 3.7 迁移测试方法

**测试位置**：`tests/run_tests.gd`，新增 `_test_player_profile()`、`_test_save_migrator()`、`_test_save_repository()`。

**夹具策略**：把 golden JSON 以字符串常量内嵌在测试脚本里，避免 `res://tests/fixtures/*.json` 在导出/导入流程中的格式差异；每个用例使用独立临时目录 `user://test_saves_<msec>/slot_main/`，测试结束删除。

```gdscript
# tests/run_tests.gd（示意）
const V0_GOLDEN := '{"species_id":"trex","growth_stage":2,"generation":3}'
const V1_GOLDEN := '{"save_version":1,"species_id":"raptor","growth_stage":1,"generation":2,"map_id":"canyon","best_time":99,"best_kills":5,"mystery_flag":true}'


func _test_save_migration() -> void:
	var root := "user://test_saves_%d" % Time.get_ticks_msec()
	var repo := SaveRepository.new(root, false)   # false：测试不导入真实旧档
	DirAccess.make_dir_recursive_absolute(repo.slot_dir("main"))

	# 1) v0 → 当前：补 map_id，保留物种/成长/代际
	_write_raw(repo.profile_path("main"), V0_GOLDEN)
	var r0 := repo.load_slot("main")
	check(r0.status == SaveRepository.LoadStatus.MIGRATED, "v0 档应被迁移")
	check(r0.profile.map_id == Maps.DEFAULT_MAP_ID, "v0 档应补默认地图")
	check(r0.profile.species_id == "trex", "v0 档应保留物种")
	check(r0.profile.growth_stage == 2, "v0 档应保留成长阶段")

	# 2) 未知字段保留：load → save → 再 load
	_write_raw(repo.profile_path("main"), V1_GOLDEN)
	var r1 := repo.load_slot("main")
	check(r1.profile.extra_fields.has("mystery_flag"), "未知字段应进入 extra_fields")
	repo.save_profile(r1.profile, SaveRepository.SaveReason.MANUAL)
	var r1b := repo.load_slot("main")
	check(bool(r1b.profile.extra_fields.get("mystery_flag", false)), "未知字段应跨一次写入保留")

	# 3) 缺字段/越界：补默认 + 钳制
	_write_raw(repo.profile_path("main"), '{"save_version":1,"species_id":"nope","growth_stage":99,"generation":0,"map_id":"nope"}')
	var r2 := repo.load_slot("main")
	check(r2.profile.species_id == DinoSpecies.ID_RAPTOR, "未知物种应回退迅猛龙")
	check(r2.profile.growth_stage == DinoSpecies.MAX_STAGE, "成长阶段应钳制到上限")
	check(r2.profile.generation == 1, "代际应钳制到 1")
	check(r2.profile.map_id == Maps.DEFAULT_MAP_ID, "未知地图应回退默认")

	# 4) 未来版本：隔离 + 只读 + 不覆盖
	_write_raw(repo.profile_path("main"), '{"save_version":99,"species_id":"anky"}')
	var r3 := repo.load_slot("main")
	check(r3.status == SaveRepository.LoadStatus.FUTURE_VERSION, "未来版本应被拒绝")
	check(r3.read_only, "未来版本应标记只读")
	check(not FileAccess.file_exists(repo.profile_path("main")), "未来版本原文件应被隔离移走")
	check(_count_files(repo.slot_dir("main"), "future-v99-") == 1, "应存在未来版本隔离文件")

	# 5) 损坏 + 备份恢复：先写一份好档，再写一份坏档
	_write_raw(repo.profile_path("main"), V1_GOLDEN)
	repo.save_profile(r1.profile, SaveRepository.SaveReason.MANUAL)  # 生成 .bak
	_write_raw(repo.profile_path("main"), "not json{{")
	var r4 := repo.load_slot("main")
	check(r4.status == SaveRepository.LoadStatus.RECOVERED, "损坏档应从 .bak 恢复")
	check(r4.profile.species_id != "", "恢复后应有有效 profile")

	# 6) 原子写：无 .tmp 残留；第二次写生成 .bak
	check(not FileAccess.file_exists(repo.profile_path("main") + ".tmp"), "写完不应残留 .tmp")
	check(FileAccess.file_exists(repo.profile_path("main") + ".bak"), "覆盖写应生成 .bak")

	# 7) 缺失档：不产生文件、has_progress=false
	var empty := SaveRepository.new("user://test_empty_%d" % Time.get_ticks_msec(), false)
	var r5 := empty.load_slot("main")
	check(r5.status == SaveRepository.LoadStatus.MISSING, "无档应为 MISSING")
	check(not r5.has_progress, "无档 has_progress 应为 false")
```

**断言清单（建议至少 20 条）**：

| 类别 | 断言 |
|---|---|
| v0 迁移 | 状态为 `MIGRATED`；`map_id` 补默认；其余字段不丢 |
| 未来版本 | 状态 `FUTURE_VERSION`；`read_only=true`；原文件被隔离；不生成当前档 |
| 损坏 | 状态 `CORRUPT` 或 `RECOVERED`；corrupt 隔离文件存在；备份有效则恢复 |
| 校验和 | 篡改任一字段 → 校验失败 → 走恢复/损坏分支；无校验和旧档可通过 |
| 未知字段 | 一次 load→save→load 后仍在 `extra_fields` |
| 钳制 | 物种/地图/成长/代际/负数全部回退或钳制 |
| 原子性 | 无 `.tmp`；第二次写有 `.bak`；`.bak.1` 轮换 |
| 迁移失败 | 删除中间步骤（临时把 `CURRENT_VERSION` 调高）→ 返回空 → 按损坏处理 |
| 槽位 | 两个临时目录互不影响；`list_slots` 能列出各自的 `slot_id` |
| 兼容门面 | `SaveManager.load_save()` 对无档/损坏返回仅 `map_id`，与旧行为一致 |

### 3.8 多槽位与云存档扩展点（现在不做，接口要留）

**已经留好的扩展点**：

1. **路径参数化**：所有读写都走 `load_slot(slot_id)` / `profile.slot_id`，不存在全局单文件常量。
2. **profile 预留字段**：`revision`、`updated_at`、`slot_id` 从 v1 就写入，云同步不需要再加迁移。
3. **`LoadResult.read_only`**：未来版本/云端只读冲突时，UI/写入方有明确信号。
4. **`list_slots()`**：返回槽位元数据，可直接驱动槽位选择 UI。
5. **待补字段**：`device_id`（每安装生成一次，存 `user://device_id`）、`cloud_revision`、`last_synced_at`。这些要到真正接云时再加，避免现在写无用数据。

**后端抽象接口（建议下一步加，当前可不实现）**：

```gdscript
class_name SaveBackend
extends RefCounted
## 存储后端抽象：本地默认实现；未来 CloudSaveBackend 实现同一接口。
## Repository 不感知路径之外的东西；云同步只替换 backend + 增加 sync 流程。

func read_text(path: String) -> String:
	return ""

func write_text_atomic(path: String, text: String) -> Error:
	return ERR_UNAVAILABLE

func exists(path: String) -> bool:
	return false

func list_files(dir: String) -> PackedStringArray:
	return PackedStringArray()

func remove(path: String) -> Error:
	return ERR_UNAVAILABLE

func mtime(path: String) -> int:
	return 0
```

**云冲突策略（现在只定规则，不写实现）**：

| 情况 | 处理 |
|---|---|
| 本地 `revision >` 云端 | 上传本地，云端旧版进冲突备份 |
| 云端 `revision >` 本地 | 下载云端，本地旧版进备份 |
| `revision` 相同、checksum 相同 | 已同步，无操作 |
| `revision` 相同、checksum 不同 | 视为分叉：保留两份（`profile.conflict-local` / `profile.conflict-cloud`），让玩家选或按 `updated_at` 选新 |
| 任一侧版本 `>CURRENT` | 该侧只读，不自动合并；提示升级客户端 |

**原则**：云同步永远不直接调用 `save_profile()` 覆盖对端；先 `load_slot` 比较 `revision/checksum`，再决定。否则会重演现在 Main/PlayerDino 的丢更新问题，只是把冲突方从两个脚本换成两台设备。

### 3.9 存档写入时机与冲突处理

**唯一写入者原则**：只有 `Main` 能调用 `save_profile()`。`PlayerDino`、`SpeciesSelect`、`HUD`、`PauseMenu` 都只读 profile 或发出“事实信号”。

| 时机 | 触发点 | 同步/延迟 | 理由 | 冲突处理 |
|---|---|---|---|---|
| 新局确认 | `LOADING` 开始、`is_continue=false` | 同步立即写 | 玩家已选物种/地图，哪怕开局崩溃也不丢选择 | 在加载开始只写一次；加载中不再写 |
| 进化 | `Main._on_player_growth_changed` 检测 `stage > profile.growth_stage` | 同步立即写 | 成长是玩家最在意的进度；频率低（一局 ≤4 次） | 先更新内存 profile 再写；失败保留 dirty 标记 |
| 死亡 | `DEAD` 进入 | 同步立即写 | `generation+1`、`best_*` 必须在重生前落盘 | 取消待执行的自动存档；本次写为最高优先级 |
| 手动保存 | 暂停菜单“保存”（建议新增） | 同步 | 玩家可控的安全点 | 与自动存档去重：同一 `revision` 不重复写 |
| 定时自动存档 | 仅 `PLAYING`，每 30–60 秒；仅 dirty 时 | 同步小文件 | 防 Android 后台杀进程丢进度 | 用“最新 profile 快照”写，不排队旧快照 |
| 进后台 | `NOTIFICATION_APPLICATION_PAUSED`（Android/iOS） | 同步 | 移动端唯一可靠的收尾点 | 与死亡/进化同帧时只写一次；`revision` 幂等 |
| 回主菜单 | `MENU` 进入、reload 之前 | 同步 | 清场前最后一次落盘 | 先写再 reload；失败也继续回菜单（不能卡死） |

**冲突处理细则**：

1. **禁止 read-modify-write**：所有调用方都持有同一个 `profile` 对象；写盘是“整快照提交”，不是“读盘再改”。这从根上消除 Main/PlayerDino 的丢更新。
2. **单一 dirty 标记**：`Main._profile_dirty = true` 由进化/最佳成绩变化置位；自动存档只在 dirty 时写，写完清除。死亡/手动/回菜单为强制写，不受 dirty 限制。
3. **同一帧多次请求合并**：`Main` 用 `_save_pending_reason` 记录最高优先级（DEATH > MANUAL > EVOLUTION > START > AUTOSAVE），在本帧末或下一次安全点执行一次；不要在一个事件里连续写两次。
4. **失败重试**：写失败时保留 dirty，不弹致命错误；下一次自动存档/回菜单再试。连续失败 3 次才提示玩家“存档写入失败”。
5. **不保存运行期瞬时值**：血量/饥饿/口渴/体力/坐标/世界时间都不进存档（当前也不进）；避免高频写入与“读档回到一半状态”的设计负担。
6. **`best_time` / `best_kills` 只增不减**：`maxi(old, new)` 在 Main 内完成，Repository 不再做业务判断。
7. **LOADING/PAUSED 的写入门禁**：`LOADING` 只允许 `START`；`PAUSED` 允许 `MANUAL`；`PLAYING` 允许 `EVOLUTION/AUTOSAVE`；`DEAD` 允许 `DEATH`；`MENU` 允许 `MENU`。Repository 可只记录 reason，门禁由 Main 保证。

### 3.10 从现有 `SaveManager` 迁移的可运行中间态

> 目标：每一步都能编译、能开局、能死亡重开、能导出 APK；不搞一次性替换。

| 步骤 | 改动 | 可运行中间态 | 验收 |
|---|---|---|---|
| S0 | 新增 `PlayerProfile.gd`、`SaveMigrator.gd`、`SaveRepository.gd`；不改任何调用方 | 旧逻辑完全不变，新代码只被单测引用 | 现有 47 条断言仍全过；新增迁移单测通过 |
| S1 | `SaveManager` 退化为兼容门面：`load_save()` 调 `SaveRepository.shared().load_main()`，`write_save(d)` 转成 profile 后保存；旧路径常量指向新 `profile.json` | Main/PlayerDino/SpeciesSelect 仍按旧 API 工作；首次启动自动导入 `user://save.json` | 无档/完整档/损坏档/未来档四路径与旧行为一致（按 3.7 的兼容断言） |
| S2 | Main 改读 `profile`；`SpeciesSelect` 改为注入 `profile + has_progress`；**删除 `PlayerDino._save_progress()`，进化改由 Main 的 `growth_changed` 处理器写** | 双写消失；存档只在 Main 发生；游戏可玩 | 进化、死亡、重开、回菜单四路径 `generation/growth_stage/species_id` 一致；`rg "write_save|_save_progress"` 只剩门面 |
| S3 | 接入 3.9 的写入时机（START/EVOLUTION/DEATH/MANUAL/AUTOSAVE/APP_PAUSE/MENU）；加 `NOTIFICATION_APPLICATION_PAUSED` | 自动存档与后台保存生效 | 后台杀进程后重开进度不丢；同一帧无重复写 |
| S4 | 保留 `list_slots()` 与 `SaveBackend` 接口骨架；不接 UI | 单槽可用，多槽 API 可测 | 双临时槽位互不影响；`list_slots` 元数据正确 |
| S5 | 删除 `SaveManager` 门面；测试改用 `SaveRepository` 临时目录；更新 `ARCHITECTURE.md/PROGRESS.md/QA.md` | 全仓只有 `SaveRepository` 访问 `user://` | `rg "user://"` 仅命中 Repository/GameState/Achievements/测试；CI 全绿 |

**兼容门面示例**：

```gdscript
# scripts/data/SaveManager.gd（过渡期门面，S5 删除）
class_name SaveManager
extends RefCounted

const CURRENT_VERSION := SaveRepository.CURRENT_VERSION

static func load_save() -> Dictionary:
	var res := SaveRepository.shared().load_main()
	var status := res.status
	if status == SaveRepository.LoadStatus.MISSING or status == SaveRepository.LoadStatus.CORRUPT or status == SaveRepository.LoadStatus.FUTURE_VERSION:
		return {"map_id": Maps.DEFAULT_MAP_ID}   # 保持旧行为：无档/坏档只给默认地图
	var d := res.profile.to_dict()
	d["save_version"] = CURRENT_VERSION
	return d

static func write_save(d: Dictionary) -> void:
	var p := PlayerProfile.from_dict(d, "main")
	SaveRepository.shared().save_profile(p, SaveRepository.SaveReason.MANUAL)

static func has_save() -> bool:
	return SaveRepository.shared().load_main().status != SaveRepository.LoadStatus.MISSING

static func has_progress() -> bool:
	return SaveRepository.shared().has_progress("main")
```

**测试影响（必须同步修改，否则会误报）**：

- `tests/run_tests.gd:119-165` 直接删除 `user://save.json` / `.tmp`；新路径是 `user://saves/slot_main/profile.json`，需要改删 `profile.json`、`.tmp`、`.bak`、`.bak.1`、`.corrupt-*`、`.future-*`。**每条用例前都要清 `.bak`**，否则“损坏档应回退默认”会因为上一条用例留下的有效备份而变成“恢复成功”。
- 旧测试“写入部分档后 `has_progress()==false`”依赖 `write_save` 保留字典原样；新架构的档案是完整快照，这条语义会变。建议改为“无档/损坏档 `has_progress()==false`；完整档 `true`”，并在 S1 的门面里用 `has_progress` 状态位保持旧行为。
- 测试 `save_version` 断言仍为 1；若 S1 后启用 v2，同步更新断言与迁移用例。

---

## 4. 落地顺序与验收

### 4.1 推荐顺序（尊重 `docs/PROGRESS.md` 的“先存档、后状态机”）

```
S0 新增存档三件套（无调用方）
  → S1 SaveManager 兼容门面 + 旧档导入
  → S2 Main 单写 + 删除 PlayerDino 双写
  → G0 GameFlow 只“镜像”旧标志（不改门禁）
  → G1 门禁切到 flow.state（删 is_over/_game_started）
  → G2 HUD/PauseMenu/TouchControls 订阅状态（删 _is_dead、paused 直写）
  → G3 加载/死亡/菜单收进状态钩子 + epoch 取消
  → S3 写入时机 + 后台保存
  → G4/S4 测试、文档、删除 skip_select 与 SaveManager 门面
```

**为什么存档先做**：GameFlow 的 `DEAD/MENU/LOADING` 钩子最终都要调用保存；如果先上状态机，写盘点会在 Main 里被改写两次。先把“怎么写”收口，再决定“何时写”。

### 4.2 每步验收（项目既有口径）

| 验收项 | 命令 / 标准 |
|---|---|
| 导入零错误 | `XDG_DATA_HOME=/workspace/tools/godotdata XDG_CONFIG_HOME=/workspace/tools/godotconfig /workspace/tools/Godot_v4.4.1-stable_linux.x86_64 --headless --path /workspace/dino-new --import`，`SCRIPT ERROR` = 0 |
| 单测 | headless 跑 `tests/run_tests.gd`，`FAILED: 0`，断言数只增不减 |
| 冒烟 | `--headless --quit-after 16`，过滤后无脚本错误 |
| 全链路 | 选图→选种→加载→游玩→暂停→继续→死亡→重生→回菜单；状态日志顺序正确，重开后 `paused=false` |
| 存档矩阵 | 无档/完整档/缺字段/损坏/有备份损坏/未来版本/旧 `user://save.json` 七条路径 |
| APK | 可导出、`apksigner` v1/v2/v3 通过（本轮不要求真机） |

> 注意：`class_name` 新增后必须先重建全局类缓存，否则会报 “Could not find type X”（`HANDOVER.md` 已知陷阱 1）。

---

## 5. 风险与回退

| # | 风险 | 触发信号 | 缓解 | 回退 |
|---|---|---|---|---|
| R1 | 旧 `LOADING` 协程在回菜单后继续建节点 | 菜单里突然出现 HUD/玩家，或 `dynamic` 子节点数上涨 | 每个 `await` 后检查 `epoch == flow.load_epoch`；`MENU` 先取消令牌再 reload | 保留 `_game_started` 旧门禁一个版本，双门禁并存 |
| R2 | `BOOT→MENU` 误触发 `reload_current_scene` 死循环 | 启动后无限重载/闪屏 | `_enter_menu` 先判断 `flow.previous == BOOT`，初始 MENU 只显示选图 | 回退到 `_ready` 直接 `_show_map_select()` |
| R3 | `paused=true` 被带进新场景 | 回菜单后按钮点不动，物理静止 | `GameFlow` 退出 PAUSED 解除；`Main._exit_tree` 兜底解除；`MENU` 进入再解除 | `reload` 前显式 `get_tree().paused=false` |
| R4 | 死亡重复触发 | 连续两次死亡屏、generation 多 +1 | `DEAD` 状态早退 + `PlayerDino.is_dead` 实体幂等 + `transition` 拒绝自转移 | 保留 `is_over` 旧守卫一个版本 |
| R5 | HUD 在状态已切到 PLAYING 后才创建，漏掉一次转移 | 暂停菜单初次不显示/死亡面板不出现 | `bind` 后立即 `_apply_flow_state(flow.state)` | 在 `state_entered` 后延迟一帧再应用 |
| R6 | 未知字段被旧版本覆盖 | 回退旧版本后新字段消失 | `PlayerProfile.extra_fields` + `to_dict` 合并；测试 load→save→load | 读取时若发现未来字段，整档只读 |
| R7 | 未来版本档被覆盖 | 玩家降级后进度丢失 | 隔离原文件 + `read_only` + 不自动写 | 手动恢复 `.future-vN-*` |
| R8 | 迁移链缺步骤导致坏档 | 加载回退默认，玩家进度丢失 | 迁移前自动 `.bak`；`migrate` 缺步骤 fail closed；golden 测试 | 保留旧档隔离文件，人工恢复 |
| R9 | JSON int/float 误用 | `generation` 变 `3.0`、数组下标报错 | 所有读取 `int()`；写入前 `int()`；roundtrip 测试 | — |
| R10 | 校验和误伤手工编辑 | 玩家改档后无法加载 | 校验失败走“隔离 + 备份恢复”，不直接删除；日志说明 | 关闭 checksum 校验（保留字段） |
| R11 | `rename_absolute` 在目标存在时行为异常 | 保存返回非 OK，`.tmp` 残留 | 官方文档明确“存在且非写保护会覆盖”；检查返回值并保留 `.bak` | 改为“删旧 + rename”，但会短暂无主档，不推荐 |
| R12 | 自动存档与死亡同帧写两次 | `revision` 跳 2、磁盘抖动 | `Main` 合并 reason，取最高优先级，一帧最多写一次 | 关自动存档，仅关键点写 |
| R13 | Android 后台被杀时正在写 | 重启后档损坏 | tmp + 回读校验 + rename；`APPLICATION_PAUSED` 同步刷写 | 从 `.bak` 恢复 |
| R14 | 又新增 autoload | 启动顺序/测试隔离变差 | 明确 `GameFlow`/`SaveRepository` 由 Main 持有；autoload 保持 3 个 | 不引入 |
| R15 | 6 态与文档 8 态分叉 | 新人按文档实现出 8 态 | 落地时同步改 `ARCHITECTURE.md/PROGRESS.md` | 保留 8 态表但注明 MAP/SPECIES 为 MENU 子视图 |

---

## 6. 引用

### 6.1 Godot 官方文档（4.4）

1. [Node — Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_node.html)（`process_mode` 枚举、`NOTIFICATION_APPLICATION_PAUSED=2015`）
2. [Pausing games — Godot 4.4](https://docs.godotengine.org/en/4.4/tutorials/scripting/pausing_games.html)（暂停语义、信号仍送达、物理全局停止）
3. [SceneTree — Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_scenetree.html)（`paused` 的行为说明）
4. [Saving games — Godot 4.4](https://docs.godotengine.org/en/4.4/tutorials/io/saving_games.html)（JSON + `user://` 官方示例）
5. [JSON — Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_json.html)（`stringify(data, indent, sort_keys, full_precision)`；数字统一为 float）
6. [DirAccess — Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_diraccess.html)（`rename`：目标存在且非写保护会被覆盖）
7. [FileAccess — Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_fileaccess.html)（`open/flush/close/get_open_error`）
8. [String — Godot 4.4](https://docs.godotengine.org/en/4.4/classes/class_string.html)（`sha256_text()`）
9. [Handling quit requests — Godot 4.4](https://docs.godotengine.org/en/4.4/tutorials/inputs/handling_quit_requests.html)（移动端用 `NOTIFICATION_APPLICATION_PAUSED` 做收尾）

### 6.2 状态机实践

10. [Make a Finite State Machine in Godot 4 — GDQuest（2026-04 更新）](https://www.gdquest.com/library/pattern_finite_state_machine/)（单变量 vs 节点式 FSM、布尔变量问题）
11. [State Machines in Godot 4.3+ — LobeHub Skill](https://lobehub.com/skills/jame581-godotprompter-state-machine)（Enum / Node / Resource 三种 FSM 的复杂度与适用边界）
12. [Godot 4 Enemy AI Tutorial — Coding Quests（2026）](https://codingquests.io/blog/godot-4-enemy-ai-tutorial)（状态自持转移 vs 中央控制器）

### 6.3 存档迁移与安全

13. [Reliable Save Migration in Unity and Godot — GamineAI（2026-04）](https://www.gamineai.com/blog/reliable-save-migration-unity-godot-old-files-2026)（版本头、迁移链、golden 文件、备份）
14. [Game Save Best Practices for Godot — Bugnet（2026-03）](https://bugnet.io/blog/game-save-best-practices-godot)（`user://`、原子写、版本与迁移）
15. [Building a Save System in Godot 4 — Godot Learning（2026-01）](https://godotlearning.com/blog/godot-4-save-system-tutorial)（原子写、槽位、自动存档）
16. [Saving and Loading Games in Godot 4 — GDQuest（2026-10 更新）](https://www.gdquest.com/library/save_game_godot4/)（资源加载会执行代码的安全警告）
17. [JSON vs ConfigFile vs Resource in Godot 4 — DEV（2026-10）](https://dev.to/saltmire/json-vs-configfile-vs-resource-in-godot-4-which-save-format-and-when-31a8)（三种格式对照；JSON 不执行代码）
18. [EasyStore — Godot Asset Library（2026-07）](https://godotengine.org/asset-library/asset/5138)（多后端、槽位、云同步、冲突策略的现成参考，本项目不引入依赖）

---

## 附录 A：代码索引（当前 HEAD）

| 主题 | 文件:行 |
|---|---|
| 六个标志 | `Main.gd:28/48/51`、`PauseMenu.gd:36/42/267`、`HUD.gd:34/91/167`、`PlayerDino.gd:102` |
| 开局加载协程 | `Main.gd:156-241`、`_preload_world_assets:291-348` |
| 死亡与重开 | `Main.gd:506-585` |
| 回菜单 | `Main.gd:603-607`、`PauseMenu.gd:264-268` |
| `_process` 门禁 | `Main.gd:616-638` |
| 存档读写 | `Main.gd:148-169/511-517/560-563`、`PlayerDino.gd:819-824`、`SaveManager.gd:12-56` |
| 选种读档 | `SpeciesSelect.gd:13-23` |
| 存档测试 | `tests/run_tests.gd:101-165` |
| 暂停输入复位 | `TouchControls.gd:63-83` |
| 加载遮罩 | `LoadingScreen.gd:14-38` |
| 架构阶段 B/D | `docs/ARCHITECTURE.md:189-215` |
| 已知遗留 | `docs/PROGRESS.md:63-71` |

## 附录 B：建议新增文件

| 文件 | 职责 | 预计行数 |
|---|---|---|
| `scripts/core/GameFlow.gd` | 六态转移表、暂停唯一写者、epoch、world_ready | ~170 |
| `scripts/data/PlayerProfile.gd` | typed 内存模型、默认/钳制、未知字段保留 | ~90 |
| `scripts/data/SaveMigrator.gd` | vN→vN+1 纯函数链 | ~70 |
| `scripts/data/SaveRepository.gd` | 唯一 IO、原子写、备份、校验、隔离、槽位 | ~260 |
| `scripts/data/SaveBackend.gd`（S4，可暂缓） | 本地/云后端接口 | ~30 |
| `tests/run_tests.gd`（修改） | 迁移/仓库/状态机断言 | +150 |

> 行数为估算，不作为验收口径；实际以“导入 0 错误 + 单测全过 + headless 16s 0 错误”为准。
