class_name PlayerDino
extends CharacterBody3D
## 玩家恐龙：第三人称操控 + 真实生存系统（血量 / 饥饿 / 口渴 / 体力）
## + 真实成长（按进食从幼体长到霸主）+ 物种技能（冲锋 / 集群 / 重甲 / 威压）+ 饮水
## 物理层 layer 2 (Player)，collision_mask = layer 1 (World) + layer 4 (Trigger)
##
## 设计目标（对照《诅咒之岛》）：
## - 你是一只真实的恐龙，要同时管理饥饿、口渴、体力，不能无限狂奔
## - 成长靠“吃对的食物”积累，而非生硬的计数
## - 死亡保留成长（写入存档），下一局接着变强

# ---------- 信号（供 Main / HUD 使用） ----------
signal health_changed(current_hp: int, max_hp: int)
signal hunger_changed(current: int, maximum: int)
signal thirst_changed(current: int, maximum: int)
signal stamina_changed(current: int, maximum: int)
signal growth_changed(stage_index: int, stage_name: String, progress: float)
signal died
signal kill_made                      # 玩家击杀了一只 AI（用于计分）
signal banner(text: String)           # 大字提示（成长 / 技能）
signal hint(text: String)             # 上下文小提示（饮水等）
signal egg_laid(egg: DinoEgg)         # 产下自己的蛋（代际机制，交 Main 挂树）

# ---------- 由 Main 在 add_child 之前赋值 ----------
var species_id: String = DinoSpecies.ID_RAPTOR
var start_growth_stage: int = 0
var generation: int = 1
var map_radius: float = 140.0

# ---------- 生存数值（上限与衰减，标 [PLACEHOLDER] 待手感调） ----------
const HUNGER_MAX: int = 100
const HUNGER_INTERVAL: float = 14.0      # 每 14s 掉 1 点饥饿（满→空约 23 分钟）
const STARVE_INTERVAL: float = 5.0       # 饥饿为 0 时每 5s
const STARVE_DAMAGE: int = 6             # 饿死掉血

const THIRST_MAX: int = 100
const THIRST_INTERVAL: float = 12.0      # 每 12s 掉 1 点口渴（冲刺时倍率减半）
const THIRST_SPRINT_MULT: float = 0.5    # 冲刺时口渴消耗翻倍（间隔减半）
const THIRST_STARVE_INTERVAL: float = 4.0
const THIRST_STARVE_DAMAGE: int = 5      # 渴死掉血

const STAMINA_MAX: int = 100
const STAMINA_DRAIN: float = 22.0        # 冲刺每秒耗体力
const STAMINA_REGEN: float = 14.0        # 不冲刺每秒回体力
const STAMINA_LOCK: float = 18.0         # 体力低于此值强制步行，直到回满到该值以上

# 进食回复量
const MEAT_HUNGER: int = 28
const MEAT_HEAL: int = 8
const PLANT_HUNGER: int = 10
const PLANT_THIRST: int = 4
const PLANT_HEAL: int = 4

# 技能参数
const CHARGE_DURATION: float = 0.5
const CHARGE_COOLDOWN: float = 4.0
const CHARGE_SPEED_MULT: float = 2.0
const CHARGE_REACH: float = 3.0
const PACK_RADIUS: float = 14.0
const PACK_SPEED_BONUS: float = 0.12
const DRINK_RATE: float = 45.0           # 每秒回渴速度
const DRINK_SLOW: float = 0.4            # 喝水时移动减速

# 产蛋（代际机制）：在巢穴吃饱后产下自己的蛋，死亡后从蛋重生
const EGG_SCENE: PackedScene = preload("res://scenes/DinoEgg.tscn")
const LAY_HUNGER_MIN: int = 70           # 饥饿 > 70% 才产蛋
const LAY_HUNGER_COST: int = 25          # 产蛋消耗的饥饿
const LAY_COOLDOWN: float = 60.0         # 产蛋冷却（秒）
const LAY_NEST_RADIUS: float = 10.0      # 巢穴判定半径（比巢穴回血半径宽）
const NEST_SCAN_INTERVAL: float = 0.5    # 巢穴范围扫描节流（秒），不逐帧扫组

const BITE_REACH: float = 3.4
const BITE_COOLDOWN: float = 0.3

# 尸体拖拽：按住咬键叼起附近尸体拖在身前（先出嘴再叼取；松开/再按/死亡即放下）
const DRAG_PICKUP_RANGE: float = 3.5   # 叼取判定半径（米）
const DRAG_DISTANCE: float = 2.2       # 叼住时尸体保持在身前的距离（米）
const DRAG_STAMINA_MULT: float = 1.5   # 叼尸移动的体力消耗倍率（拖拽很费力）
const DRAG_SCAN_INTERVAL: float = 0.2  # 叼取扫描节流（秒），不逐帧扫组

const GRAVITY: float = 19.6

# ---------- 运行时状态 ----------
var species: DinoSpecies.SpeciesDef
var growth_stage: int = 0
var growth_meals: int = 0                # 当前阶段已进食次数

var current_health: int = 100
var max_health: int = 100

# 生存数值纯逻辑层：public 成员名保持不变，外部（HUD / TutorialGuide）仍按属性读取
var _vitals: Vitals = Vitals.new()
var current_hunger: int:
	get:
		return _vitals.hunger
var current_thirst: int:
	get:
		return _vitals.thirst
var current_stamina: int:
	get:
		return _vitals.stamina

# 矿物盐等临时增益
var buff_timer: float = 0.0
var buff_speed_mult: float = 1.0
var buff_dmg_mult: float = 1.0

var is_dead: bool = false
var bite_cooldown_timer: float = 0.0
var is_biting: bool = false
var bite_anim_timer: float = 0.0

var camera_yaw: float = 0.0
var cam_pitch: float = CAM_PITCH

# 相机模式：第一人称 / 第二人称(越肩近身) / 第三人称
enum CameraMode { FIRST, SHOULDER, THIRD }
var camera_mode: CameraMode = CameraMode.THIRD
signal camera_mode_changed(mode_name: String)
var touch_move_input: Vector2 = Vector2.ZERO
var _look_delta: Vector2 = Vector2.ZERO
var touch_drink: bool = false
var _f_held: bool = false
var _was_drinking: bool = false

# 技能
var charge_cooldown_timer: float = 0.0
var charging: bool = false
var charge_timer: float = 0.0
var charged_targets: Array = []
var pack_bonus: bool = false

# 上一帧已广播的整数值：只在整数真的变化时才 emit，避免 HUD 每物理帧重写 Label
var _last_hunger: int = -1
var _last_thirst: int = -1
var _last_stamina: int = -1

# 尸体拖拽状态
var _dragged_corpse: AICorpse = null   # 正在叼住的尸体（null = 未叼）
var _dragged_corpse_layer: int = 0     # 叼住时尸体的原始 collision_layer（放下时恢复）
var _touch_bite_hold: bool = false     # 触屏咬键长按电平（TouchControls.bite_hold_changed 桥接）
var _bite_hold_consumed: bool = false  # 本次按住会话已叼过/已失效：防"放下后按住未松立刻重叼"
var _drag_scan_timer: float = DRAG_SCAN_INTERVAL  # 叼取扫描节流计时（初值=首扫延迟：长按 0.2s 后才叼取，轻点咬击不误叼）
var _terrain_ref: TerrainGenerator = null  # 地形引用缓存（Main 未注入本脚本，惰性按类型查找一次）

# 提示 / 产蛋 / 巢穴扫描
var current_hint: String = ""
var lay_cooldown_timer: float = 0.0      # 产蛋冷却倒计时
var _nest_scan_timer: float = 0.0        # 巢穴扫描节流
var _was_in_nest: bool = false           # 上一扫描点是否在巢穴范围（沿触发提示）

# 派生属性（受物种 + 成长影响）
var bite_damage: int = 10
var walk_speed: float = 5.0
var run_speed: float = 9.0
var bite_cooldown: float = 0.3
var current_size: float = 1.0
var visual_base_scale: Vector3 = Vector3.ONE

# 节点引用
@onready var dino_visual: DinoVisual = $DinoVisual
@onready var bite_area: Area3D = $BiteArea
@onready var spring_arm: SpringArm3D = $SpringArm3D
@onready var camera: Camera3D = $SpringArm3D/Camera3D

# 音效（程序化合成 WAV）
const SFX_BITE := preload("res://assets/audio/bite.wav")
const SFX_HURT := preload("res://assets/audio/hurt.wav")
const SFX_EAT := preload("res://assets/audio/eat.wav")
const SFX_DRINK := preload("res://assets/audio/drink.wav")
const SFX_EVOLVE := preload("res://assets/audio/evolve.wav")
const SFX_DEATH := preload("res://assets/audio/death.wav")
var sfx: AudioStreamPlayer

const CAM_YAW_SPEED: float = 2.2
const CAM_PITCH: float = -0.35
const CAM_PITCH_MIN: float = -1.15
const CAM_PITCH_MAX: float = -0.05
const CAM_HEIGHT: float = 1.7
const LOOK_SENS: float = 0.005      # 每像素拖动的偏航弧度
const PITCH_SENS: float = 0.004     # 每像素拖动的俯仰弧度
const ROT_SPEED: float = 12.0
const ACCEL: float = 18.0
const JUMP_VELOCITY: float = 7.5

func _ready() -> void:
	add_to_group(Groups.PLAYER)
	sfx = AudioStreamPlayer.new()
	sfx.volume_db = -4.0
	sfx.bus = AudioManager.BUS_SFX
	add_child(sfx)
	species = DinoSpecies.by_id(species_id)
	if species == null:
		species = DinoSpecies.by_id(DinoSpecies.ID_RAPTOR)
	growth_stage = clampi(start_growth_stage, 0, DinoSpecies.MAX_STAGE)
	growth_meals = 0
	_apply_species_appearance()
	_apply_growth_stats()
	current_health = max_health
	_vitals.setup(HUNGER_MAX, THIRST_MAX, STAMINA_MAX, _vitals_rates())
	# 摄像机不继承玩家旋转
	spring_arm.top_level = true
	spring_arm.spring_length = 5.5
	spring_arm.rotation = Vector3(cam_pitch, 0.0, 0.0)
	spring_arm.add_excluded_object(get_rid())
	# 初始信号
	health_changed.emit(current_health, max_health)
	_emit_hunger()
	_emit_thirst()
	_emit_stamina()
	_growth_signal()
	banner.emit("你是一只%s（%s）" % [species.name, DinoSpecies.stage_name(growth_stage)])


# ================= 外观（加载现成 3D 模型） =================
func _apply_species_appearance() -> void:
	dino_visual.setup(species_id, species.body_color, species.dark_color)
	dino_visual.set_size(current_size)


# ================= 属性（物种 × 成长） =================
func _apply_growth_stats() -> void:
	max_health = int(round(species.max_health * GrowthRules.stage_multiplier(growth_stage, "hp")))
	bite_damage = int(round(species.bite_damage * GrowthRules.stage_multiplier(growth_stage, "dmg")))
	walk_speed = species.walk_speed * GrowthRules.stage_multiplier(growth_stage, "spd")
	run_speed = species.run_speed * GrowthRules.stage_multiplier(growth_stage, "spd")
	bite_cooldown = species.bite_cooldown
	current_size = species.size * GrowthRules.stage_multiplier(growth_stage, "size")
	visual_base_scale = Vector3(current_size, current_size, current_size)
	dino_visual.set_size(current_size)


func _growth_signal() -> void:
	var info: Dictionary = DinoSpecies.stage_info(growth_stage)
	var need: float = GrowthRules.next_stage_progress(growth_stage)
	var progress: float = float(growth_meals) / need if need < 9000.0 else 1.0
	growth_changed.emit(growth_stage, info["name"], progress)


## 注入 Vitals 的全部速率：数值仍由本脚本常量定义，Domain 不硬编码平衡值
func _vitals_rates() -> Dictionary:
	return {
		"hunger_interval": HUNGER_INTERVAL,
		"thirst_interval": THIRST_INTERVAL,
		"thirst_sprint_mult": THIRST_SPRINT_MULT,
		"stamina_drain": STAMINA_DRAIN,
		"stamina_regen": STAMINA_REGEN,
		"stamina_lock": STAMINA_LOCK,
		"drag_stamina_mult": DRAG_STAMINA_MULT,
		"drink_rate": DRINK_RATE,
		"starve_interval": STARVE_INTERVAL,
		"starve_damage": STARVE_DAMAGE,
		"thirst_starve_interval": THIRST_STARVE_INTERVAL,
		"thirst_starve_damage": THIRST_STARVE_DAMAGE,
		"eat_meat_hunger": MEAT_HUNGER,
		"eat_plant_hunger": PLANT_HUNGER,
		"eat_plant_thirst": PLANT_THIRST,
		"eat_egg_hunger": 0,
		"survival_step_once": false,
	}


# ================= 输入 =================
func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event.is_action_pressed("bite"):
		if _dragged_corpse != null:
			# 实现选择：叼住状态下按咬键优先执行"放下"而非出嘴——
			# 长按语义下"按住+有尸体=拖"，叼住仍出嘴会"既咬又拖"（还会咬中自己叼的尸体）；
			# 置 consumed 防止按住未松时放下又被自动重叼，需松开重按
			_drop_corpse()
			_bite_hold_consumed = true
		else:
			try_bite()
	elif event.is_action_pressed("jump"):
		try_jump()


func _physics_process(delta: float) -> void:
	if is_dead:
		_update_camera_position()
		return

	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# 移动输入
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	input_dir += touch_move_input
	input_dir = input_dir.limit_length(1.0)

	var cam_basis: Basis = camera.global_basis
	var forward: Vector3 = -cam_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = cam_basis.x
	right.y = 0.0
	right = right.normalized()
	var move_dir: Vector3 = (forward * -input_dir.y + right * input_dir.x)
	if move_dir.length() > 0.01:
		move_dir = move_dir.normalized()

	# 咬键长按电平：触屏桥接 + 键盘 J 物理键，两路输入统一驱动叼尸/拖拽。
	# 不能读 "bite" 动作：该动作含鼠标左键，且项目开启了 emulate_touch_from_mouse，
	# 桌面在右半屏拖视角时 "bite" 会持续为真 → 误触发自动叼尸/自动咬。
	# 点按攻击仍走 _unhandled_input 的 "bite"（鼠标左键单击照常出嘴）。
	var bite_held: bool = _touch_bite_hold or Input.is_physical_key_pressed(KEY_J)
	if not bite_held:
		_bite_hold_consumed = false
	_update_dragging(delta, bite_held)

	# 体力与冲刺
	_update_stamina(delta, move_dir.length() > 0.1)
	# 增益计时
	if buff_timer > 0.0:
		buff_timer -= delta
		if buff_timer <= 0.0:
			buff_speed_mult = 1.0
			buff_dmg_mult = 1.0
	var sprinting: bool = Input.is_action_pressed("sprint") and can_sprint() and move_dir.length() > 0.1
	var speed: float = walk_speed
	if sprinting:
		speed = run_speed

	# 技能：冲锋中强行加速
	if charging:
		speed = run_speed * CHARGE_SPEED_MULT
		charge_timer -= delta
		if charge_timer <= 0.0:
			charging = false
		else:
			_do_charge_damage()

	# 饮水：在水里按住饮水键（独立动作 drink，默认键 E；触屏为饮水按钮），移动减速且不能冲刺。
	# 饮水判定不再直接轮询物理键 KEY_E，改走 InputMap 动作层（可重绑定、与触屏按钮同语义）；
	# cam_right 的 E 绑定按需求保留不动
	var drink_held := Input.is_action_pressed("drink") or touch_drink
	# 技能：键盘 F 边沿触发
	if Input.is_key_pressed(KEY_F) and not _f_held:
		try_ability()
	_f_held = Input.is_key_pressed(KEY_F)
	var drinking: bool = false
	if drink_held and _is_in_water():
		drinking = true
		# 45 点/秒按物理步长结算：小数部分由 Vitals 累积，满 1 点才加到口渴上
		_vitals.drink(delta)
		_emit_thirst()
		speed *= DRINK_SLOW
		_update_drink_hint(true)
		if not _was_drinking:
			_sfx(SFX_DRINK)
			_was_drinking = true
	else:
		_update_drink_hint(false)
		_was_drinking = false

	var target_vel: Vector3 = move_dir * speed * buff_speed_mult
	var accel: float = ACCEL * delta
	velocity.x = move_toward(velocity.x, target_vel.x, accel)
	velocity.z = move_toward(velocity.z, target_vel.z, accel)

	if move_dir.length() > 0.1 and not drinking:
		var target_yaw: float = atan2(-move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, ROT_SPEED * delta)

	# 计时器
	if bite_cooldown_timer > 0.0:
		bite_cooldown_timer -= delta
	if is_biting:
		bite_anim_timer -= delta
		if bite_anim_timer <= 0.0:
			is_biting = false
	if charge_cooldown_timer > 0.0:
		charge_cooldown_timer -= delta
	if lay_cooldown_timer > 0.0:
		lay_cooldown_timer -= delta

	# 摄像机旋转 Q/E（桌面）或触屏拖动（手机）
	var yaw_input: float = 0.0
	if Input.is_action_pressed("cam_left"):
		yaw_input += 1.0
	if Input.is_action_pressed("cam_right"):
		yaw_input -= 1.0
	camera_yaw += yaw_input * CAM_YAW_SPEED * delta
	if _look_delta != Vector2.ZERO:
		camera_yaw += _look_delta.x * LOOK_SENS
		cam_pitch = clampf(cam_pitch + _look_delta.y * PITCH_SENS, _pitch_limits().x, _pitch_limits().y)
		_look_delta = Vector2.ZERO

	_update_camera_position()
	_update_vitals(delta, sprinting)
	var moving := move_dir.length() > 0.1 and not drinking
	dino_visual.play_locomotion(moving, speed / maxf(walk_speed, 0.001))
	move_and_slide()
	_clamp_to_map()


# ================= 体力 =================
func _update_stamina(delta: float, moving: bool) -> void:
	# 本帧是否想冲刺：由输入 / 移动 / 当前体力共同决定（与旧实现同一帧内先判后扣）
	var sprinting: bool = Input.is_action_pressed("sprint") and moving and can_sprint()
	var dragging: bool = _dragged_corpse != null and moving
	_vitals.tick_stamina(delta, sprinting, dragging)
	_emit_stamina()

func can_sprint() -> bool:
	return _vitals.can_sprint()


# ================= 生存数值衰减 =================
func _update_vitals(delta: float, sprinting: bool) -> void:
	# 22/60 ≈ 0.37 这类步长下整数结算会恒为 0，Vitals 内部用 float 累加余数
	_vitals.tick_survival(delta, sprinting)
	_emit_hunger()
	_emit_thirst()
	# 饿死 / 渴死伤害仍由 Node 走 take_damage，保留受伤表现与死亡流程
	var starve_damage: int = _vitals.pull_starve_damage()
	if starve_damage > 0:
		take_damage(starve_damage)
	var thirst_damage: int = _vitals.pull_thirst_damage()
	if thirst_damage > 0:
		take_damage(thirst_damage)


# ================= 数值广播（仅在整数变化时发信号，避免 HUD 每帧重排） =================
func _emit_hunger() -> void:
	if current_hunger == _last_hunger:
		return
	_last_hunger = current_hunger
	hunger_changed.emit(current_hunger, HUNGER_MAX)


func _emit_thirst() -> void:
	if current_thirst == _last_thirst:
		return
	_last_thirst = current_thirst
	thirst_changed.emit(current_thirst, THIRST_MAX)


func _emit_stamina() -> void:
	if current_stamina == _last_stamina:
		return
	_last_stamina = current_stamina
	stamina_changed.emit(current_stamina, STAMINA_MAX)


# ================= 摄像机 =================
func _update_camera_position() -> void:
	# 眼睛高度随体型缩放；不同模式用不同臂长与侧偏
	var eye: float = CAM_HEIGHT * current_size
	var len: float = 5.5
	var side: float = 0.0
	match camera_mode:
		CameraMode.FIRST:
			len = 0.05
		CameraMode.SHOULDER:
			len = 2.6
			side = 0.7 * current_size
		CameraMode.THIRD:
			len = 5.5
	spring_arm.spring_length = len
	# 越肩：把相机支点沿"右方"平移，保持始终在右肩后
	var right := Vector3(cos(camera_yaw), 0.0, -sin(camera_yaw))
	spring_arm.global_position = global_position + Vector3(0.0, eye, 0.0) + right * side
	spring_arm.rotation = Vector3(cam_pitch, camera_yaw, 0.0)


## 切换相机模式（第一/越肩/第三），并广播当前模式名
func cycle_camera_mode() -> void:
	camera_mode = (camera_mode + 1) % 3
	_update_camera_position()
	var name_: String = "第三人称"
	match camera_mode:
		CameraMode.FIRST: name_ = "第一人称"
		CameraMode.SHOULDER: name_ = "越肩视角"
		CameraMode.THIRD: name_ = "第三人称"
	camera_mode_changed.emit(name_)


## 俯仰限制随模式变化（第一人称可抬头看山）
func _pitch_limits() -> Vector2:
	if camera_mode == CameraMode.FIRST:
		return Vector2(-1.45, 0.6)
	return Vector2(CAM_PITCH_MIN, CAM_PITCH_MAX)


## 触屏视角拖动增量（由 TouchControls.LookZone 调用），乘以用户灵敏度设置
func add_look_delta(d: Vector2) -> void:
	_look_delta += d * float(GameState.get_setting("look_sensitivity", 1.0))


# ================= 咬击 =================
func try_bite() -> void:
	if is_dead or bite_cooldown_timer > 0.0:
		return
	bite_cooldown_timer = maxf(bite_cooldown, BITE_COOLDOWN)
	is_biting = true
	bite_anim_timer = 0.3
	dino_visual.play_attack()
	_sfx(SFX_BITE)
	# 命中检测：附近前方的 AI 或 尸体
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for node in get_tree().get_nodes_in_group(Groups.AI):
		if _bite_hit(node, fwd):
			# 补传 self:让 AI 记住仇恨来源是玩家,便于其反击/逃跑决策
			(node as AIDino).take_damage(_effective_bite(), true, self)
	for node in get_tree().get_nodes_in_group(Groups.CORPSE):
		if _bite_hit(node, fwd):
			var corpse: AICorpse = node as AICorpse
			if corpse.try_eat():
				_eat_meal("meat")

func _bite_hit(node: Node3D, fwd: Vector3) -> bool:
	if not is_instance_valid(node):
		return false
	var to: Vector3 = node.global_position - global_position
	to.y = 0.0
	if to.length() > BITE_REACH:
		return false
	to = to.normalized()
	return fwd.dot(to) > 0.2

func _effective_bite() -> int:
	# 基础伤害已含成长倍率，故 growth_mult 传 1.0；取整顺序：集群 → 限时增益
	var dmg: int = CombatRules.bite_damage(
			bite_damage, 1.0, false, CombatRules.PACK_DMG_BONUS if pack_bonus else 0.0)
	return CombatRules.apply_multiplier(dmg, buff_dmg_mult)


## 矿物盐等限时增益
func apply_buff(dur: float, spd: float, dmg: float) -> void:
	buff_timer = dur
	buff_speed_mult = spd
	buff_dmg_mult = dmg


# ================= 尸体拖拽 =================
## 触屏咬键长按电平（由 TouchControls.bite_hold_changed 反向接线调用）；松开即放下
func set_bite_hold(held: bool) -> void:
	_touch_bite_hold = held
	if not held:
		_drop_corpse()


## 每物理帧驱动拖拽：叼住时把尸体拉到身前贴地；未叼住且咬键按住时节流扫描可叼尸体
func _update_dragging(delta: float, bite_held: bool) -> void:
	if _dragged_corpse != null:
		# 键盘路径松开咬键即放下（触屏路径已由 set_bite_hold(false) 在事件层放下），与叼取时的提示文案一致
		if not bite_held:
			_drop_corpse()
			return
		if is_instance_valid(_dragged_corpse):
			# 尸体固定在身前 2.2m，y 经地形高度贴地（静止时同样保持在前方）
			var fwd: Vector3 = -global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var pos: Vector3 = global_position + fwd * DRAG_DISTANCE
			pos.y = _ground_y(pos.x, pos.z)
			_dragged_corpse.global_position = pos
		else:
			_dragged_corpse = null
		return
	# 叼取判定：咬键先出嘴（键盘边沿在 _unhandled_input，触屏点按经 bite_pressed 桥接
	# try_bite），电平叼取需持续按住 0.2s（首扫延迟）后才发生——轻点只咬不叼，长按才叼取
	if not bite_held or _bite_hold_consumed:
		return
	_drag_scan_timer -= delta
	if _drag_scan_timer > 0.0:
		return
	_drag_scan_timer = DRAG_SCAN_INTERVAL
	var best: AICorpse = null
	var best_d: float = DRAG_PICKUP_RANGE
	for n in get_tree().get_nodes_in_group(Groups.CORPSE):
		var c := n as AICorpse
		if c == null or not is_instance_valid(c):
			continue
		var d: float = global_position.distance_to(c.global_position)
		if d < best_d:
			best_d = d
			best = c
	if best != null:
		_dragged_corpse = best
		best.set_dragged(true)
		# 尸体是 StaticBody3D（collision_layer = 4），玩家 collision_mask 含该层；叼在身前 2.2m 时
		# 两者碰撞体重叠约 0.3m → 每帧被自己的尸体顶退抖动。叼住瞬间关闭尸体的碰撞层（记原值），
		# 放下时恢复；尸体被 queue_free 后 is_instance_valid 为假，自然跳过恢复
		_dragged_corpse_layer = best.collision_layer
		best.collision_layer = 0
		_bite_hold_consumed = true   # 本次按住只叼一次：点按放下后不会立刻自动重叼
		banner.emit("叼起了尸体")
		hint.emit("松开咬键放下尸体；再按咬键也可放下")


## 放下尸体（松开咬键 / 叼住时再按咬键 / 死亡），恢复其腐烂计时
func _drop_corpse() -> void:
	if _dragged_corpse != null and is_instance_valid(_dragged_corpse):
		# 恢复叼住前的碰撞层，让尸体重新成为可站立的实体（已 queue_free 的尸体不可达，跳过）
		_dragged_corpse.collision_layer = _dragged_corpse_layer
		_dragged_corpse.set_dragged(false)
		# 放下即收嘴：占住一次常规咬击冷却。触屏"松开放下"时 Button 会同帧补发
		# bite_pressed（try_bite），不占冷却会把刚放下的尸体当场咬掉一口；
		# 键盘侧 0.3s 即常规咬击间隔，无手感差异
		bite_cooldown_timer = maxf(bite_cooldown, BITE_COOLDOWN)
	_dragged_corpse = null


## 地形高度查询：Main 未给本脚本注入地形引用，惰性按类型在主场景树中查找一次并缓存
## （仅首次叼尸时有一次遍历开销；失败退回玩家自身高度，不阻塞拖拽）
func _ground_y(x: float, z: float) -> float:
	if _terrain_ref == null or not is_instance_valid(_terrain_ref):
		var scene_root: Node = get_tree().current_scene
		if scene_root != null:
			var found: Array[Node] = scene_root.find_children("*", "TerrainGenerator", true, false)
			if not found.is_empty():
				_terrain_ref = found[0] as TerrainGenerator
	if _terrain_ref != null and is_instance_valid(_terrain_ref):
		return _terrain_ref.get_height(x, z)
	return global_position.y


## 巢穴回体力（夹取并广播）
func restore_stamina(amt: int) -> void:
	_vitals.restore_stamina(amt)
	_emit_stamina()


# ================= 技能 =================
## 是否拥有「冲锋」主动技能（决定技能按钮是否显示）
func has_charge_ability() -> bool:
	return species.active == DinoSpecies.ActiveAbility.CHARGE


func try_ability() -> void:
	if is_dead or species.active != DinoSpecies.ActiveAbility.CHARGE:
		return
	if charge_cooldown_timer > 0.0 or charging:
		return
	charging = true
	charge_timer = CHARGE_DURATION
	charge_cooldown_timer = CHARGE_COOLDOWN
	charged_targets.clear()
	banner.emit("冲锋！")

func _do_charge_damage() -> void:
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	# 冲锋伤害 = 当前有效咬击 × 2.2（由 CombatRules 统一取整）
	var dmg: int = CombatRules.bite_damage(_effective_bite(), 1.0, true, 0.0)
	for node in get_tree().get_nodes_in_group(Groups.AI):
		if node in charged_targets:
			continue
		if not is_instance_valid(node):
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		if to.length() > CHARGE_REACH or fwd.dot(to.normalized()) < 0.3:
			continue
		charged_targets.append(node)
		# 补传 self:冲锋撞击同样让 AI 记住仇恨来源
		(node as AIDino).take_damage(dmg, true, self)
		# 击退
		var kb: Vector3 = to.normalized() * 6.0
		(node as AIDino).velocity += kb


# ================= 进食 / 成长 =================
func _eat_meal(kind: String) -> void:
	if kind == "meat":
		if species.diet != DinoSpecies.Diet.CARNIVORE:
			return
		_sfx(SFX_EAT)
		_vitals.eat("meat")
		_emit_hunger()
		heal(MEAT_HEAL)
		_add_growth_meal(GrowthRules.MEAL_MEAT)
	elif kind == "plant":
		if species.diet != DinoSpecies.Diet.HERBIVORE:
			return
		_sfx(SFX_EAT)
		_vitals.eat("plant")
		_emit_hunger()
		_emit_thirst()
		heal(PLANT_HEAL)
		_add_growth_meal(GrowthRules.MEAL_PLANT)

## 草食玩家被植物自动吃到时调用（由 Foliage 触发）
func on_eat_plant() -> void:
	if is_dead:
		return
	_eat_meal("plant")

func _add_growth_meal(meal_kind: int) -> void:
	growth_meals = int(GrowthRules.add_progress(float(growth_meals), meal_kind))
	var need: float = GrowthRules.next_stage_progress(growth_stage)
	if float(growth_meals) >= need and growth_stage < DinoSpecies.MAX_STAGE:
		growth_meals = 0
		growth_stage += 1
		_apply_growth_stats()
		current_health = max_health
		health_changed.emit(current_health, max_health)
		banner.emit("成长为 %s！" % DinoSpecies.stage_name(growth_stage))
		_sfx(SFX_EVOLVE)
		_play_glow()
		_save_progress()
	_growth_signal()


# ================= 产蛋（代际机制） =================
## 巢穴语境：0.5s 节流扫描 NEST 类资源点。进入范围时提示玩法；
## 条件齐备（范围内 + 饥饿 > 70% + 冷却结束）自动产下自己的蛋。
func _update_nest_context(delta: float) -> void:
	if is_dead:
		return
	_nest_scan_timer -= delta
	if _nest_scan_timer > 0.0:
		return
	_nest_scan_timer = NEST_SCAN_INTERVAL
	var in_nest: bool = _nearest_nest_distance() <= LAY_NEST_RADIUS
	if in_nest and not _was_in_nest:
		hint.emit("在巢穴吃饱后可以产蛋")
	_was_in_nest = in_nest
	if in_nest:
		_try_lay_egg()


## 最近 NEST 类资源点的平面距离（场上无巢穴返回 INF）
func _nearest_nest_distance() -> float:
	var best: float = INF
	for n in get_tree().get_nodes_in_group(Groups.RESOURCE):
		var rp := n as ResourcePoint
		if rp == null or rp.point_type != ResourcePoint.Type.NEST:
			continue
		var d: float = Vector2(global_position.x - rp.global_position.x, global_position.z - rp.global_position.z).length()
		best = minf(best, d)
	return best


## 产蛋：扣 25 点饥饿，蛋带当前成长阶段快照（死亡重开时取“蛋快照与存档较大者”），
## 经 egg_laid 信号交 Main 挂树；首次产蛋解锁成就（unlock 幂等，无需判重）。
func _try_lay_egg() -> void:
	if lay_cooldown_timer > 0.0 or current_hunger <= LAY_HUNGER_MIN:
		return
	lay_cooldown_timer = LAY_COOLDOWN
	_vitals.consume_hunger(LAY_HUNGER_COST)
	_emit_hunger()
	var egg := EGG_SCENE.instantiate() as DinoEgg
	egg.species_id = species.id
	egg.owner_player = true
	egg.growth_stage_snapshot = growth_stage
	# 放脚下：蛋尚未入树，直接设局部位置（dynamic 容器为原点恒等变换，局部即世界坐标）
	egg.position = global_position
	egg_laid.emit(egg)
	banner.emit("你产下了一枚蛋，它将延续你的血脉")
	Achievements.unlock("nest_first")


# ================= 受伤 / 死亡 =================
func take_damage(amount: int, attacker: Node = null) -> void:
	if is_dead:
		return
	var dmg: int = amount
	if species.passive == DinoSpecies.PassiveAbility.DEFENSE:
		dmg = CombatRules.apply_defense(amount)
	current_health = maxi(0, current_health - dmg)
	health_changed.emit(current_health, max_health)
	dino_visual.pulse_damage()
	_sfx(SFX_HURT)
	# 落血反馈:Android 手柄震动 40ms;死亡流程走 _die() 不震动,且 is_dead 早退保证死后不再触发
	if OS.has_feature("android"):
		Input.vibrate_handheld(40)
	if current_health <= 0:
		_die()

func heal(amount: int) -> void:
	if is_dead:
		return
	current_health = mini(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)

func _die() -> void:
	if is_dead:
		return
	is_dead = true
	_drop_corpse()   # 死亡叼不住：尸体落地并恢复其腐烂计时
	remove_from_group(Groups.PLAYER)
	died.emit()
	dino_visual.shrink_death()
	_sfx(SFX_DEATH)
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position:y", global_position.y - 0.4, 0.5)

func _save_progress() -> void:
	# 进化时只提交 growth_stage：先读再写，保留 generation / map_id / best_* 等生涯字段。
	# 注意：死亡结算（generation+1、best_*）的唯一权威仍是 Main，这里绝不写那些字段，
	# 否则会与 Main 的整快照提交形成双写竞争。
	var profile: PlayerProfile = SaveRepository.load_profile()
	profile.growth_stage = growth_stage
	SaveRepository.save_profile(profile)


# ================= 工具 =================
func _is_in_water() -> bool:
	for w in get_tree().get_nodes_in_group(Groups.WATER):
		if is_instance_valid(w) and w is WaterSource:
			var ws: WaterSource = w as WaterSource
			var d: float = Vector2(global_position.x - ws.global_position.x, global_position.z - ws.global_position.z).length()
			if d <= ws.radius:
				return true
	return false

func _clamp_to_map() -> void:
	var d: float = Vector2(global_position.x, global_position.z).length()
	if d > map_radius:
		var inward: Vector3 = Vector3(-global_position.x, 0.0, -global_position.z).normalized()
		global_position.x = inward.x * map_radius
		global_position.z = inward.z * map_radius
		velocity.x = 0.0
		velocity.z = 0.0


## 播放音效（sfx 节点在 _ready 创建，独立于 is_dead）
func _sfx(s: AudioStream) -> void:
	if sfx == null or not is_instance_valid(sfx) or s == null:
		return
	sfx.stream = s
	sfx.play()


func _update_drink_hint(in_water: bool) -> void:
	var h := ""
	if in_water and current_thirst < THIRST_MAX:
		h = "按住 饮水键 喝水"
	if h != current_hint:
		current_hint = h
		hint.emit(h)

func get_size() -> float:
	return current_size

func is_carnivore() -> bool:
	return species.diet == DinoSpecies.Diet.CARNIVORE

func set_move_input(vec: Vector2) -> void:
	touch_move_input = vec

func set_drink_held(v: bool) -> void:
	touch_drink = v

## 触发跳跃
func try_jump() -> void:
	if is_dead:
		return
	if is_on_floor():
		velocity.y = JUMP_VELOCITY

# 集群加成：附近有同物种同伴时提升速度/伤害
func _update_pack() -> void:
	pack_bonus = false
	if species.passive != DinoSpecies.PassiveAbility.PACK:
		return
	for node in get_tree().get_nodes_in_group(Groups.AI):
		if is_instance_valid(node) and node != self and (node as AIDino).species.id == species.id:
			if global_position.distance_to(node.global_position) <= PACK_RADIUS:
				pack_bonus = true
				break

func _play_glow() -> void:
	dino_visual.glow()


func _process(delta: float) -> void:
	_update_pack()
	_update_nest_context(delta)
