class_name AIDino
extends CharacterBody3D
## AI 恐龙：构成真实食物链的生态个体
## - 肉食龙猎食草食龙 / 更小的肉食龙 / 尸体 / 可捕食的玩家
## - 草食龙吃植物、聚群、躲避比自己大的肉食龙
## - 每只恐龙都有独立的饥饿 / 口渴，会饿死，也懂得喝水
## - 不再“无脑追玩家”：只有当玩家是猎物（草食）或比自己弱小时才会被猎食
##
## 物理层 layer 3 (AI)，collision_mask = layer 1 (World) + layer 2 (Player)

signal died(node: AIDino, by_player: bool)

# 由 Main 在 add_child 之前赋值
var species_id: String = "raptor"
var start_growth_stage: int = 0
var map_radius: float = 80.0

const SENSE_RADIUS: float = 24.0
const FLEE_RADIUS: float = 18.0
const ATTACK_RANGE: float = 2.8
const GRAZE_RANGE: float = 2.2

const HUNGER_MAX: int = 100
const HUNGER_INTERVAL: float = 50.0
const STARVE_INTERVAL: float = 6.0
const STARVE_DAMAGE: int = 4
const THIRST_MAX: int = 100
const THIRST_INTERVAL: float = 45.0
const DRINK_RATE: float = 40.0
const DECISION_INTERVAL: float = 0.25

const AI_MEAT_HUNGER: int = 30
const AI_MEAT_HEAL: int = 10
const AI_PLANT_HUNGER: int = 12
const AI_PLANT_HEAL: int = 4

const GRAVITY: float = 19.6
const ROT_SPEED: float = 6.0
const ACCEL: float = 10.0

var species: DinoSpecies.SpeciesDef
var growth_stage: int = 0
var current_size: float = 1.0

var current_health: int = 100
var max_health: int = 100
var current_hunger: int = HUNGER_MAX
var current_thirst: int = THIRST_MAX
var bite_damage: int = 10
var walk_speed: float = 5.0
var run_speed: float = 9.0
var attack_cooldown: float = 0.6
var is_dead: bool = false

var hunger_timer: float = 0.0
var thirst_timer: float = 0.0
var starve_timer: float = 0.0
var decision_timer: float = 0.0
var attack_timer: float = 0.0
var wander_timer: float = 0.0
var wander_dir: Vector3 = Vector3.ZERO
var wander_min_pause: float = 1.0

var hunt_target: Node3D = null
var flee_target: Node3D = null
var last_by_player: bool = false

@onready var state_controller: StateController = $StateController
@onready var dino_visual: DinoVisual = $DinoVisual


func _ready() -> void:
	add_to_group("ai")
	species = DinoSpecies.by_id(species_id)
	if species == null:
		species = DinoSpecies.by_id("raptor")
	growth_stage = clampi(start_growth_stage, 0, DinoSpecies.MAX_STAGE)
	dino_visual.setup(species_id, species.body_color, species.dark_color)
	_apply_stats()
	current_health = max_health
	current_hunger = HUNGER_MAX
	current_thirst = THIRST_MAX
	state_controller.transition_to(StateController.State.WANDER)


func _apply_stats() -> void:
	var info: Dictionary = DinoSpecies.stage_info(growth_stage)
	max_health = int(round(species.max_health * info["hp"]))
	bite_damage = int(round(species.bite_damage * info["dmg"]))
	walk_speed = species.walk_speed * info["spd"] * 0.8
	run_speed = species.run_speed * info["spd"] * 0.8
	attack_cooldown = species.bite_cooldown
	current_size = species.size * info["size"]
	dino_visual.set_size(current_size)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	decision_timer += delta
	if decision_timer >= DECISION_INTERVAL:
		decision_timer = 0.0
		_decide()

	_act(delta)

	if attack_timer > 0.0:
		attack_timer -= delta

	_update_vitals(delta)
	_clamp_to_map()
	dino_visual.play_locomotion(velocity.length() > 0.5, velocity.length() / maxf(run_speed, 0.001))
	move_and_slide()


# ================= 决策 =================
func _decide() -> void:
	var threat: Node3D = _find_threat()
	if threat != null:
		flee_target = threat
		state_controller.transition_to(StateController.State.FLEE)
		return

	if species.diet == DinoSpecies.Diet.CARNIVORE:
		var prey: Node3D = _find_prey()
		if prey != null and (current_hunger < 65 or _prey_weak(prey)):
			hunt_target = prey
			state_controller.transition_to(StateController.State.HUNT)
			return
		if current_thirst < 35 and _nearest_water() != null:
			state_controller.transition_to(StateController.State.DRINK)
			return
		state_controller.transition_to(StateController.State.WANDER)
	else:
		if current_hunger < 55 and _nearest_plant() != null:
			state_controller.transition_to(StateController.State.GRAZE)
			return
		if current_thirst < 35 and _nearest_water() != null:
			state_controller.transition_to(StateController.State.DRINK)
			return
		state_controller.transition_to(StateController.State.WANDER)


func _prey_weak(prey: Node3D) -> bool:
	if prey is PlayerDino:
		return (prey as PlayerDino).get_size() < current_size * 0.7
	if prey is AIDino:
		return (prey as AIDino).current_size < current_size * 0.7
	return false


# ================= 行为 =================
func _act(delta: float) -> void:
	match state_controller.current_state:
		StateController.State.WANDER:
			_wander(delta)
		StateController.State.HUNT:
			_hunt(delta)
		StateController.State.FLEE:
			_flee(delta)
		StateController.State.GRAZE:
			_graze(delta)
		StateController.State.DRINK:
			_drink(delta)
		_:
			_wander(delta)


func _wander(delta: float) -> void:
	wander_timer -= delta
	if wander_timer <= 0.0:
		if randf() < 0.3:
			wander_dir = Vector3.ZERO
			wander_timer = wander_min_pause + randf()
		else:
			var angle: float = randf() * TAU
			wander_dir = Vector3(sin(angle), 0.0, cos(angle))
			# 草食龙：向同伴群中心轻微偏移，形成兽群
			if species.diet == DinoSpecies.Diet.HERBIVORE:
				var herd: Vector3 = _herd_center()
				if herd != Vector3.ZERO:
					wander_dir = wander_dir.lerp(herd - global_position, 0.4).normalized()
			wander_timer = 2.5 + randf() * 2.0
	_apply_movement(wander_dir, walk_speed, delta)


func _hunt(delta: float) -> void:
	if hunt_target == null or not is_instance_valid(hunt_target):
		state_controller.transition_to(StateController.State.WANDER)
		return
	var to: Vector3 = hunt_target.global_position - global_position
	to.y = 0.0
	var d: float = to.length()
	if d > SENSE_RADIUS * 1.3:
		hunt_target = null
		state_controller.transition_to(StateController.State.WANDER)
		return
	_apply_movement(to.normalized(), run_speed, delta)
	# 接触攻击
	if d <= ATTACK_RANGE and attack_timer <= 0.0:
		attack_timer = attack_cooldown
		if hunt_target is PlayerDino:
			(hunt_target as PlayerDino).take_damage(_effective_bite())
		elif hunt_target is AIDino:
			(hunt_target as AIDino).take_damage(_effective_bite(), false)
		elif hunt_target is AICorpse:
			if (hunt_target as AICorpse).try_eat():
				_eat(AI_MEAT_HUNGER, AI_MEAT_HEAL)


func _graze(delta: float) -> void:
	var plant: Node3D = _nearest_plant()
	if plant == null:
		_wander(delta)
		return
	var to: Vector3 = plant.global_position - global_position
	to.y = 0.0
	if to.length() > GRAZE_RANGE:
		_apply_movement(to.normalized(), walk_speed, delta)
	# 实际进食由 Foliage 的 body_entered 自动触发 on_eat_plant()


func _drink(delta: float) -> void:
	var water: WaterSource = _nearest_water()
	if water == null:
		_wander(delta)
		return
	var to: Vector2 = Vector2(water.global_position.x - global_position.x, water.global_position.z - global_position.z)
	if to.length() > water.radius - 1.0:
		_apply_movement(Vector3(to.x, 0.0, to.y).normalized(), walk_speed, delta)
	else:
		current_thirst = mini(current_thirst + int(DRINK_RATE * delta), THIRST_MAX)
		_apply_movement(Vector3.ZERO, 0.0, delta)


func _flee(delta: float) -> void:
	if flee_target == null or not is_instance_valid(flee_target):
		state_controller.transition_to(StateController.State.WANDER)
		return
	var away: Vector3 = global_position - flee_target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf() - 0.5, 0.0, randf() - 0.5)
	_apply_movement(away.normalized(), run_speed, delta)


# ================= 生存数值 =================
func _update_vitals(delta: float) -> void:
	hunger_timer += delta
	if hunger_timer >= HUNGER_INTERVAL:
		hunger_timer -= HUNGER_INTERVAL
		current_hunger = maxi(0, current_hunger - 1)
	if current_hunger <= 0:
		starve_timer += delta
		if starve_timer >= STARVE_INTERVAL:
			starve_timer -= STARVE_INTERVAL
			take_damage(STARVE_DAMAGE, false)
	thirst_timer += delta
	if thirst_timer >= THIRST_INTERVAL:
		thirst_timer -= THIRST_INTERVAL
		current_thirst = maxi(0, current_thirst - 1)


func _eat(hunger_amt: int, heal_amt: int) -> void:
	if is_dead:
		return
	current_hunger = mini(current_hunger + hunger_amt, HUNGER_MAX)
	current_health = mini(current_health + heal_amt, max_health)


# 草食 AI 被植物碰到时调用（由 Foliage 触发）
func on_eat_plant() -> void:
	_eat(AI_PLANT_HUNGER, AI_PLANT_HEAL)


# ================= 受伤 / 死亡 =================
func take_damage(amount: int, by_player: bool) -> void:
	if is_dead:
		return
	last_by_player = by_player
	var dmg: int = amount
	if species.passive == DinoSpecies.PassiveAbility.DEFENSE:
		dmg = int(round(amount * 0.55))
	current_health = maxi(0, current_health - dmg)
	dino_visual.pulse_damage()
	if current_health <= 0:
		_die()


func _die() -> void:
	if is_dead:
		return
	is_dead = true
	state_controller.transition_to(StateController.State.DEAD)
	died.emit(self, last_by_player)
	queue_free()


func _effective_bite() -> int:
	var dmg: int = bite_damage
	if species.passive == DinoSpecies.PassiveAbility.PACK and _has_ally_near():
		dmg = int(round(dmg * 1.2))
	return dmg


func _has_ally_near() -> bool:
	for n in get_tree().get_nodes_in_group("ai"):
		if n != self and is_instance_valid(n) and (n as AIDino).species.id == species.id:
			if global_position.distance_to((n as AIDino).global_position) <= 14.0:
				return true
	return false


# ================= 查询 =================
func _player() -> PlayerDino:
	var arr: Array = get_tree().get_nodes_in_group("player")
	if arr.is_empty():
		return null
	return arr[0] as PlayerDino

func _find_threat() -> Node3D:
	var best: Node3D = null
	var best_d: float = FLEE_RADIUS
	for n in get_tree().get_nodes_in_group("ai"):
		if n == self or not is_instance_valid(n):
			continue
		var other: AIDino = n as AIDino
		if other.is_dead or other.species.diet != DinoSpecies.Diet.CARNIVORE:
			continue
		if other.current_size <= current_size * 0.85:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	var p: PlayerDino = _player()
	if p != null and not p.is_dead and p.is_carnivore() and p.get_size() > current_size * 0.85:
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
	return best

func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d: float = SENSE_RADIUS
	for n in get_tree().get_nodes_in_group("ai"):
		if n == self or not is_instance_valid(n):
			continue
		var other: AIDino = n as AIDino
		if other.is_dead:
			continue
		var edible: bool = false
		if other.species.diet == DinoSpecies.Diet.HERBIVORE:
			edible = true
		elif other.current_size < current_size * 0.9:
			edible = true
		if edible:
			var d: float = global_position.distance_to(other.global_position)
			if d < best_d:
				best_d = d
				best = other
	for c in get_tree().get_nodes_in_group("corpse"):
		if is_instance_valid(c):
			var d: float = global_position.distance_to((c as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = c as Node3D
	var p: PlayerDino = _player()
	if p != null and not p.is_dead:
		var edible: bool = (not p.is_carnivore()) or (p.get_size() < current_size * 0.9)
		if edible:
			var d: float = global_position.distance_to(p.global_position)
			if d < best_d:
				best = p
	return best

func _nearest_plant() -> Node3D:
	var best: Node3D = null
	var best_d: float = SENSE_RADIUS
	for n in get_tree().get_nodes_in_group("plant"):
		if is_instance_valid(n):
			var d: float = global_position.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
	return best

func _nearest_water() -> WaterSource:
	var best: WaterSource = null
	var best_d: float = SENSE_RADIUS
	for n in get_tree().get_nodes_in_group("water"):
		if is_instance_valid(n) and n is WaterSource:
			var ws: WaterSource = n as WaterSource
			var d: float = Vector2(global_position.x - ws.global_position.x, global_position.z - ws.global_position.z).length()
			if d < best_d:
				best_d = d
				best = ws
	return best

func _herd_center() -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var cnt: int = 0
	for n in get_tree().get_nodes_in_group("ai"):
		if n != self and is_instance_valid(n):
			var other: AIDino = n as AIDino
			if other.species.id == species.id and global_position.distance_to(other.global_position) < 30.0:
				sum += other.global_position
				cnt += 1
	return sum / cnt if cnt > 0 else Vector3.ZERO


# ================= 工具 =================
func _apply_movement(dir: Vector3, speed: float, delta: float) -> void:
	var target_vel: Vector3 = dir * speed
	var accel: float = ACCEL * delta
	velocity.x = move_toward(velocity.x, target_vel.x, accel)
	velocity.z = move_toward(velocity.z, target_vel.z, accel)
	if dir.length() > 0.1:
		var target_yaw: float = atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, ROT_SPEED * delta)

func _clamp_to_map() -> void:
	var d: float = Vector2(global_position.x, global_position.z).length()
	if d > map_radius:
		var inward: Vector3 = Vector3(-global_position.x, 0.0, -global_position.z).normalized()
		velocity.x = inward.x * run_speed
		velocity.z = inward.z * run_speed
		rotation.y = lerp_angle(rotation.y, atan2(-inward.x, -inward.z), 0.2)
