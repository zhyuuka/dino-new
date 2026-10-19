class_name TutorialGuide
extends Node
## 新手引导（自接线设计）：按序展示操作目标，玩家完成当前步后自动进入下一步；
## 全部完成后写入成就存档的"引导完成"标记（跨局不再显示）并自毁。
##
## 自接线设计（Main 仅在开局挂载一次，其余接线由本节点自己完成）：
## - Main 侧只需 TutorialGuide.new() + add_child，其余由本节点自己完成：
##   _ready 起以 0.5s 周期扫描 Groups.PLAYER 组，等待玩家出现并连接其信号；
##   玩家死亡后 Main._restart_run 会释放旧玩家并重建新玩家，本节点靠同一扫描发现
##   引用失效（已释放 / is_dead / 已退出 PLAYER 组）即自动重连新玩家。
##   重连机制选用"周期扫描"而非 get_tree().node_added：后者对每次任意节点加树都回调
##   且仍需类型过滤，0.5s 扫描（一次组查询 O(组大小)）实现更简单、代价可忽略。
## - HUD 在自身 _ready 中加入 Groups.HUD 组供本节点动态发现；死亡重开会重建 HUD，
##   同样由扫描自动重连并重显当前目标。
##
## 步骤完成判定（前一步完成才显示/判定下一步）：
## 1. 移动：_process 轮询玩家输入非零（触屏摇杆 touch_move_input 或键盘方向键）
## 2. 喝水：连接 thirst_changed，口渴值"回升"（当前值 > 上次值）即判定饮水成功
##    （草食吃植物也回升口渴，属可接受的宽判定；玩家出生满渴，需等首次自然下降后再喝）
## 3. 进食：连接 hunger_changed，饥饿值"回升"即判定吃对的食物
## 4. 成长：连接 growth_changed，stage >= 1 即完成；接续存档开局即 stage>=1 时，
##    玩家 _ready 的初始信号早于本节点接线会漏事件，故重连后按当前状态立即补判
##
## 关于"猎杀一只恐龙"原第 5 步为何删除（结论：无可靠的玩家侧命中信号，引导只做 4 步）：
## - PlayerDino.kill_made 是死信号（仅声明、全项目无 emit），不能依赖；
## - PlayerDino.is_biting / bite_anim_timer 在每次咬击尝试时都置位，无法区分"咬中"与"落空"；
## - 唯一可靠痕迹在 AIDino 私有状态（受击仇恨 _aggro_target == 玩家），但 AIDino 属
##   并行开发中被修改的文件，轮询其私有字段过于脆弱；
## - 备选"体型达 1.2 倍初始"与第 4 步同时达成（幼体 0.55 → 少年 0.75 已是 1.36 倍），无引导价值。

## 重连扫描周期（秒）：等待玩家 / HUD 出现，以及死亡重开后发现新引用
const SCAN_INTERVAL: float = 0.5

## 各步骤目标文案（下标即步骤序号）
const STEP_TEXTS: Array[String] = [
	"用左摇杆移动",
	"靠近湖边按饮水键喝水",
	"吃对的食物（肉食咬猎物 / 草食吃植物）",
	"升级到第二成长阶段",
]

var _player: PlayerDino = null
var _hud: HUD = null
var _step: int = 0
var _scan_timer: float = 0.0
var _last_thirst: int = 0
var _last_hunger: int = 0


func _ready() -> void:
	# 引导已完成（跨局存档标记）→ 永不显示，直接自毁
	if Achievements.is_tutorial_done():
		queue_free()
		return


func _process(delta: float) -> void:
	# 周期重连：发现 / 重连玩家与 HUD（死亡重开、界面重建后自动恢复）
	_scan_timer -= delta
	if _scan_timer <= 0.0:
		_scan_timer = SCAN_INTERVAL
		_reconnect()
	# 第 1 步：轮询移动输入（触屏摇杆非零 或 键盘方向键非零）
	if _step == 0 and _player != null and is_instance_valid(_player) and not _player.is_dead:
		var kb: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
		if _player.touch_move_input != Vector2.ZERO or kb != Vector2.ZERO:
			_complete_step()


## 扫描并（重）连接玩家与 HUD；引用全部有效时为无操作
func _reconnect() -> void:
	# HUD：死亡重开会重建，每次扫描取组内最新实例（无则保持 null，目标条暂不显示）
	_hud = get_tree().get_first_node_in_group(Groups.HUD) as HUD
	# 玩家：引用失效（已释放）、已死亡（等重开）或已退出 PLAYER 组时重新查找
	if _player != null and (not is_instance_valid(_player) or _player.is_dead or not _player.is_in_group(Groups.PLAYER)):
		_player = null
	if _player == null:
		var found: Node = get_tree().get_first_node_in_group(Groups.PLAYER)
		if found is PlayerDino:
			_connect_player(found as PlayerDino)
	# 玩家与 HUD 都已接上：重显当前目标（set_objective 文案未变时幂等），并补判第 4 步
	if _hud != null and _player != null and _step < STEP_TEXTS.size():
		_show_objective()
		if _step == 3 and _player.growth_stage >= 1:
			_complete_step()


## 连接玩家信号并初始化追踪状态（is_connected 防重复连接）
func _connect_player(p: PlayerDino) -> void:
	_player = p
	if not p.thirst_changed.is_connected(_on_thirst_changed):
		p.thirst_changed.connect(_on_thirst_changed)
	if not p.hunger_changed.is_connected(_on_hunger_changed):
		p.hunger_changed.connect(_on_hunger_changed)
	if not p.growth_changed.is_connected(_on_growth_changed):
		p.growth_changed.connect(_on_growth_changed)
	if not p.died.is_connected(_on_player_died):
		p.died.connect(_on_player_died)
	# 以当前值初始化"上次值"，避免把连接前的历史涨跌误判为本次引导行为
	_last_thirst = p.current_thirst
	_last_hunger = p.current_hunger


func _on_thirst_changed(current: int, _maximum: int) -> void:
	# 口渴回升（喝水 / 草食吃植物）→ 第 2 步完成；上次值恒更新，跨步骤不误判
	if current > _last_thirst and _step == 1:
		_complete_step()
	_last_thirst = current


func _on_hunger_changed(current: int, _maximum: int) -> void:
	# 饥饿回升（吃对的食物）→ 第 3 步完成
	if current > _last_hunger and _step == 2:
		_complete_step()
	_last_hunger = current


func _on_growth_changed(stage: int, _stage_name: String, _progress: float) -> void:
	# 成长到第二阶段（阶段下标 1）→ 第 4 步完成
	if stage >= 1 and _step == 3:
		_complete_step()


func _on_player_died() -> void:
	# 玩家死亡：断开引用等待 _restart_run 重建（目标文案保留，新玩家接上后原步继续）
	_player = null


## 完成当前步：进入下一步；已到最后一步则收尾自毁
func _complete_step() -> void:
	_step += 1
	if _step >= STEP_TEXTS.size():
		_finish()
		return
	_show_objective()


## 把当前步目标写到 HUD 常驻目标条
func _show_objective() -> void:
	if _hud != null and is_instance_valid(_hud) and _step < STEP_TEXTS.size():
		_hud.set_objective(STEP_TEXTS[_step])


## 全部完成：写跨局标记（成就存档内）、提示一次、清目标条、自毁
func _finish() -> void:
	Achievements.mark_tutorial_done()
	if _hud != null and is_instance_valid(_hud):
		_hud.show_hint("新手引导完成！祝你狩猎愉快。")
		_hud.clear_objective()
	queue_free()
