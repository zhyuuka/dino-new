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

# ---------- 由 Main 在 add_child 之前赋值 ----------
var species_id: String = "raptor"
var start_growth_stage: int = 0
var generation: int = 1
var map_radius: float = 140.0

# ---------- 生存数值（上限与衰减，标 [PLACEHOLDER] 待手感调） ----------
const HUNGER_MAX: int = 100
const HUNGER_INTERVAL: float = 35.0      # 每 35s 掉 1 点饥饿
const STARVE_INTERVAL: float = 5.0       # 饥饿为 0 时每 5s
const STARVE_DAMAGE: int = 6             # 饿死掉血

const THIRST_MAX: int = 100
const THIRST_INTERVAL: float = 30.0      # 每 30s 掉 1 点口渴
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
const CHARGE_DMG_MULT: float = 2.2
const CHARGE_REACH: float = 3.0
const PACK_RADIUS: float = 14.0
const PACK_SPEED_BONUS: float = 0.12
const PACK_DMG_BONUS: float = 0.20
const DEFENSE_REDUCTION: float = 0.55    # 重甲：受到伤害 ×0.55
const DRINK_RATE: float = 45.0           # 每秒回渴速度
const DRINK_SLOW: float = 0.4            # 喝水时移动减速

const BITE_REACH: float = 3.4
const BITE_COOLDOWN: float = 0.3
const GRAVITY: float = 19.6

# ---------- 运行时状态 ----------
var species: DinoSpecies.SpeciesDef
var growth_stage: int = 0
var growth_meals: int = 0                # 当前阶段已进食次数

var current_health: int = 100
var max_health: int = 100
var current_hunger: int = HUNGER_MAX
var current_thirst: int = THIRST_MAX
var current_stamina: int = STAMINA_MAX

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
var touch_move_input: Vector2 = Vector2.ZERO
var _look_delta: Vector2 = Vector2.ZERO
var touch_drink: bool = false
var _f_held: bool = false

# 技能
var charge_cooldown_timer: float = 0.0
var charging: bool = false
var charge_timer: float = 0.0
var charged_targets: Array = []
var pack_bonus: bool = false

# 衰减计时器
var hunger_timer: float = 0.0
var thirst_timer: float = 0.0
var starve_timer: float = 0.0
var thirst_starve_timer: float = 0.0
var current_hint: String = ""

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
	add_to_group("player")
	species = DinoSpecies.by_id(species_id)
	if species == null:
		species = DinoSpecies.by_id("raptor")
	growth_stage = clampi(start_growth_stage, 0, DinoSpecies.MAX_STAGE)
	growth_meals = 0
	_apply_species_appearance()
	_apply_growth_stats()
	current_health = max_health
	current_hunger = HUNGER_MAX
	current_thirst = THIRST_MAX
	current_stamina = STAMINA_MAX
	# 摄像机不继承玩家旋转
	spring_arm.top_level = true
	spring_arm.spring_length = 5.5
	spring_arm.rotation = Vector3(cam_pitch, 0.0, 0.0)
	spring_arm.add_excluded_object(get_rid())
	# 初始信号
	health_changed.emit(current_health, max_health)
	hunger_changed.emit(current_hunger, HUNGER_MAX)
	thirst_changed.emit(current_thirst, THIRST_MAX)
	stamina_changed.emit(current_stamina, STAMINA_MAX)
	_growth_signal()
	banner.emit("你是一只%s（%s）" % [species.name, DinoSpecies.stage_name(growth_stage)])


# ================= 外观（加载现成 3D 模型） =================
func _apply_species_appearance() -> void:
	dino_visual.setup(species_id, species.body_color, species.dark_color)
	dino_visual.set_size(current_size)


# ================= 属性（物种 × 成长） =================
func _apply_growth_stats() -> void:
	var info: Dictionary = DinoSpecies.stage_info(growth_stage)
	max_health = int(round(species.max_health * info["hp"]))
	bite_damage = int(round(species.bite_damage * info["dmg"]))
	walk_speed = species.walk_speed * info["spd"]
	run_speed = species.run_speed * info["spd"]
	bite_cooldown = species.bite_cooldown
	current_size = species.size * info["size"]
	visual_base_scale = Vector3(current_size, current_size, current_size)
	dino_visual.set_size(current_size)


func _growth_signal() -> void:
	var info: Dictionary = DinoSpecies.stage_info(growth_stage)
	var need: int = info["need"]
	var progress: float = float(growth_meals) / float(need) if need < 9000 else 1.0
	growth_changed.emit(growth_stage, info["name"], progress)


# ================= 输入 =================
func _unhandled_input(event: InputEvent) -> void:
	if is_dead:
		return
	if event.is_action_pressed("bite"):
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

	# 饮水：在水里按住饮水键（键盘 E 或触屏），移动减速且不能冲刺
	var drink_held := Input.is_key_pressed(KEY_E) or touch_drink
	# 技能：键盘 F 边沿触发
	if Input.is_key_pressed(KEY_F) and not _f_held:
		try_ability()
	_f_held = Input.is_key_pressed(KEY_F)
	var drinking: bool = false
	if drink_held and _is_in_water():
		drinking = true
		current_thirst = mini(current_thirst + int(DRINK_RATE * delta), THIRST_MAX)
		thirst_changed.emit(current_thirst, THIRST_MAX)
		speed *= DRINK_SLOW
		_update_drink_hint(true)
	else:
		_update_drink_hint(false)

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

	# 摄像机旋转 Q/E（桌面）或触屏拖动（手机）
	var yaw_input: float = 0.0
	if Input.is_action_pressed("cam_left"):
		yaw_input += 1.0
	if Input.is_action_pressed("cam_right"):
		yaw_input -= 1.0
	camera_yaw += yaw_input * CAM_YAW_SPEED * delta
	if _look_delta != Vector2.ZERO:
		camera_yaw += _look_delta.x * LOOK_SENS
		cam_pitch = clampf(cam_pitch + _look_delta.y * PITCH_SENS, CAM_PITCH_MIN, CAM_PITCH_MAX)
		_look_delta = Vector2.ZERO

	_update_camera_position()
	_update_vitals(delta, sprinting)
	var moving := move_dir.length() > 0.1 and not drinking
	dino_visual.play_locomotion(moving, speed / maxf(walk_speed, 0.001))
	move_and_slide()
	_clamp_to_map()


# ================= 体力 =================
func _update_stamina(delta: float, moving: bool) -> void:
	var sprinting: bool = Input.is_action_pressed("sprint") and moving and can_sprint()
	if sprinting:
		current_stamina = maxi(0, current_stamina - int(STAMINA_DRAIN * delta))
	else:
		current_stamina = mini(current_stamina + int(STAMINA_REGEN * delta), STAMINA_MAX)
	_post_stamina_check()
	stamina_changed.emit(current_stamina, STAMINA_MAX)

func can_sprint() -> bool:
	return current_stamina > 0 and not _exhausted

var _exhausted: bool = false
func _post_stamina_check() -> void:
	if current_stamina <= 0:
		_exhausted = true
	elif current_stamina >= STAMINA_LOCK:
		_exhausted = false


# ================= 生存数值衰减 =================
func _update_vitals(delta: float, sprinting: bool) -> void:
	# 饥饿
	hunger_timer += delta
	if hunger_timer >= HUNGER_INTERVAL:
		hunger_timer -= HUNGER_INTERVAL
		current_hunger = maxi(0, current_hunger - 1)
		hunger_changed.emit(current_hunger, HUNGER_MAX)
	if current_hunger <= 0:
		starve_timer += delta
		if starve_timer >= STARVE_INTERVAL:
			starve_timer -= STARVE_INTERVAL
			take_damage(STARVE_DAMAGE)
	# 口渴（冲刺时消耗翻倍）
	var ti: float = THIRST_INTERVAL * (THIRST_SPRINT_MULT if sprinting else 1.0)
	thirst_timer += delta
	if thirst_timer >= ti:
		thirst_timer -= ti
		current_thirst = maxi(0, current_thirst - 1)
		thirst_changed.emit(current_thirst, THIRST_MAX)
	if current_thirst <= 0:
		thirst_starve_timer += delta
		if thirst_starve_timer >= THIRST_STARVE_INTERVAL:
			thirst_starve_timer -= THIRST_STARVE_INTERVAL
			take_damage(THIRST_STARVE_DAMAGE)


# ================= 摄像机 =================
func _update_camera_position() -> void:
	spring_arm.global_position = global_position + Vector3(0.0, CAM_HEIGHT, 0.0)
	spring_arm.rotation = Vector3(cam_pitch, camera_yaw, 0.0)


## 触屏视角拖动增量（由 TouchControls.LookZone 调用）
func add_look_delta(d: Vector2) -> void:
	_look_delta += d


# ================= 咬击 =================
func try_bite() -> void:
	if is_dead or bite_cooldown_timer > 0.0:
		return
	bite_cooldown_timer = maxf(bite_cooldown, BITE_COOLDOWN)
	is_biting = true
	bite_anim_timer = 0.3
	dino_visual.play_attack()
	# 命中检测：附近前方的 AI 或 尸体
	var fwd: Vector3 = -global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	for node in get_tree().get_nodes_in_group("ai"):
		if _bite_hit(node, fwd):
			(node as AIDino).take_damage(_effective_bite(), true)
	for node in get_tree().get_nodes_in_group("corpse"):
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
	var dmg: int = bite_damage
	if pack_bonus:
		dmg = int(round(dmg * (1.0 + PACK_DMG_BONUS)))
	dmg = int(round(dmg * buff_dmg_mult))
	return dmg


## 矿物盐等限时增益
func apply_buff(dur: float, spd: float, dmg: float) -> void:
	buff_timer = dur
	buff_speed_mult = spd
	buff_dmg_mult = dmg


## 巢穴回体力（夹取并广播）
func restore_stamina(amt: int) -> void:
	current_stamina = mini(current_stamina + amt, STAMINA_MAX)
	stamina_changed.emit(current_stamina, STAMINA_MAX)


# ================= 技能 =================
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
	var dmg: int = int(round(_effective_bite() * CHARGE_DMG_MULT))
	for node in get_tree().get_nodes_in_group("ai"):
		if node in charged_targets:
			continue
		if not is_instance_valid(node):
			continue
		var to: Vector3 = node.global_position - global_position
		to.y = 0.0
		if to.length() > CHARGE_REACH or fwd.dot(to.normalized()) < 0.3:
			continue
		charged_targets.append(node)
		(node as AIDino).take_damage(dmg, true)
		# 击退
		var kb: Vector3 = to.normalized() * 6.0
		(node as AIDino).velocity += kb


# ================= 进食 / 成长 =================
func _eat_meal(kind: String) -> void:
	if kind == "meat":
		if species.diet != DinoSpecies.Diet.CARNIVORE:
			return
		current_hunger = mini(current_hunger + MEAT_HUNGER, HUNGER_MAX)
		hunger_changed.emit(current_hunger, HUNGER_MAX)
		heal(MEAT_HEAL)
		_add_growth_meal()
	elif kind == "plant":
		if species.diet != DinoSpecies.Diet.HERBIVORE:
			return
		current_hunger = mini(current_hunger + PLANT_HUNGER, HUNGER_MAX)
		current_thirst = mini(current_thirst + PLANT_THIRST, THIRST_MAX)
		hunger_changed.emit(current_hunger, HUNGER_MAX)
		thirst_changed.emit(current_thirst, THIRST_MAX)
		heal(PLANT_HEAL)
		_add_growth_meal()

## 草食玩家被植物自动吃到时调用（由 Foliage 触发）
func on_eat_plant() -> void:
	if is_dead:
		return
	_eat_meal("plant")

func _add_growth_meal() -> void:
	growth_meals += 1
	var need: int = DinoSpecies.stage_info(growth_stage)["need"]
	if growth_meals >= need and growth_stage < DinoSpecies.MAX_STAGE:
		growth_meals = 0
		growth_stage += 1
		_apply_growth_stats()
		current_health = max_health
		health_changed.emit(current_health, max_health)
		banner.emit("成长为 %s！" % DinoSpecies.stage_name(growth_stage))
		_play_glow()
		_save_progress()
	_growth_signal()


# ================= 受伤 / 死亡 =================
func take_damage(amount: int) -> void:
	if is_dead:
		return
	var dmg: int = amount
	if species.passive == DinoSpecies.PassiveAbility.DEFENSE:
		dmg = int(round(amount * DEFENSE_REDUCTION))
	current_health = maxi(0, current_health - dmg)
	health_changed.emit(current_health, max_health)
	dino_visual.pulse_damage()
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
	remove_from_group("player")
	died.emit()
	dino_visual.shrink_death()
	var tween: Tween = create_tween()
	tween.tween_property(self, "global_position:y", global_position.y - 0.4, 0.5)

func _save_progress() -> void:
	var d := SaveManager.load_save()
	d["species_id"] = species.id
	d["growth_stage"] = growth_stage
	d["generation"] = generation
	SaveManager.write_save(d)


# ================= 工具 =================
func _is_in_water() -> bool:
	for w in get_tree().get_nodes_in_group("water"):
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
	for node in get_tree().get_nodes_in_group("ai"):
		if is_instance_valid(node) and node != self and (node as AIDino).species.id == species.id:
			if global_position.distance_to(node.global_position) <= PACK_RADIUS:
				pack_bonus = true
				break

func _play_glow() -> void:
	dino_visual.glow()


func _process(delta: float) -> void:
	_update_pack()
