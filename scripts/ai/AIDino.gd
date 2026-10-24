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
signal egg_laid(egg: DinoEgg)

# 由 Main 在 add_child 之前赋值
var species_id: String = DinoSpecies.ID_RAPTOR
var start_growth_stage: int = 0
var map_radius: float = 80.0

const SENSE_RADIUS: float = 24.0
const FLEE_RADIUS: float = 18.0
const APEX_RADIUS: float = 24.0
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
const AGGRO_DURATION: float = 6.0          # 受击仇恨持续时间(秒)
const ATTACK_ANIM_THROTTLE: float = 1.0    # 攻击动画节流:同一目标 1 秒内不重复触发

# 领地系统:成年 AI 以落位为家盘踞一地;数值均为距 _home_pos 的半径(米)
const HOME_WANDER_RADIUS: float = 40.0     # 领地游荡半径:游荡不出 home 40m,跑出边缘即调头回家
const HOME_DEFENSE_RADIUS: float = 25.0    # 领地防御半径:肉食成年对进入 [home 25m] 且打得过者主动攻击
const HOME_FLEE_RADIUS: float = 12.0       # 草食领地警觉半径:肉食者进入 [home 12m] 提前逃跑(比 25m 被动感知更警觉)

# 繁殖产蛋:吃得饱 + 成年 + 巢穴附近才繁殖;蛋经 egg_laid 信号交 Main 挂树(AI 不持有 Main 引用)
const EGG_SCENE: PackedScene = preload("res://scenes/DinoEgg.tscn")
const LAY_HUNGER_MIN: int = 55             # 饥饿高于该值(吃得饱)才产蛋
const LAY_STAGE_MIN: int = 1               # 幼体不繁殖,成长阶段 ≥1(少年)才产蛋
const LAY_NEST_RADIUS: float = 10.0        # 距 NEST 类资源点的判定半径(米)
const LAY_COOLDOWN: float = 90.0           # 自身产蛋冷却(秒)
const LAY_MAX_EGGS: int = 10               # 全场蛋数上限(含玩家蛋)
const EGG_BITE_HUNGER: int = 10            # 偷蛋每口回复饥饿(蛋 2 口破)
const EGG_BITE_HEAL: int = 2               # 偷蛋每口回复血量
const OWN_EGG_SAFE_TIME: float = 6.0       # 自己刚产的蛋保护期(秒):产蛋后不会立刻自食
const OWN_EGG_SAFE_RADIUS: float = 3.0     # 巢边保护半径(米):3m 内任何蛋都不咬,避免同巢互食

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

# 生存数值纯逻辑层：饥饿 / 口渴（AI 无体力）；public 成员名保持不变
var _vitals: Vitals = Vitals.new()
var current_hunger: int:
	get:
		return _vitals.hunger
var current_thirst: int:
	get:
		return _vitals.thirst
var bite_damage: int = 10
var walk_speed: float = 5.0
var run_speed: float = 9.0
var attack_cooldown: float = 0.6
var is_dead: bool = false

var decision_timer: float = 0.0
var attack_timer: float = 0.0
var lay_cooldown_timer: float = 0.0        # 产蛋冷却倒计时
# 最近产下的蛋与产蛋时刻(秒):_find_prey 据此排除自己的蛋,防止饥饿 56~64 时下一个决策就咬掉
var _last_egg: DinoEgg = null
var _last_egg_time: float = 0.0
var wander_timer: float = 0.0
var wander_dir: Vector3 = Vector3.ZERO
var wander_min_pause: float = 1.0

var hunt_target: Node3D = null
var flee_target: Node3D = null
var last_by_player: bool = false
# 决策周期内缓存的最近目标：由 _decide（每 DECISION_INTERVAL 秒）刷新，
# 执行层（_graze/_drink）只消费缓存，避免每帧对全组做 O(n) 距离扫描
var _cached_plant: Node3D = null
var _cached_water: WaterSource = null
# 受击仇恨:被打后 6 秒报复窗口,由 _decide 最优先消费,超时或目标失效即清空
var _aggro_target: Node3D = null
var _aggro_timer: float = 0.0
# 攻击动画节流:记录最近一次触发的目标与剩余冷却
var _attack_anim_target: Node = null
var _attack_anim_timer: float = 0.0
# 领地:成年个体落位后记录的家(_ready 时尚未落位,延迟到首个物理帧登记);Boss 全域巡游不设领地
var _home_pos: Vector3 = Vector3.ZERO
var _has_home: bool = false
var _home_recorded: bool = false

@onready var state_controller: StateController = $StateController
@onready var dino_visual: DinoVisual = $DinoVisual


func _ready() -> void:
	add_to_group(Groups.AI)
	species = DinoSpecies.by_id(species_id)
	if species == null:
		species = DinoSpecies.by_id(DinoSpecies.ID_RAPTOR)
	growth_stage = clampi(start_growth_stage, 0, DinoSpecies.MAX_STAGE)
	dino_visual.setup(species_id, species.body_color, species.dark_color)
	_apply_stats()
	current_health = max_health
	_vitals.setup(HUNGER_MAX, THIRST_MAX, 0, _vitals_rates())
	state_controller.transition_to(StateController.State.WANDER)


func _apply_stats() -> void:
	max_health = int(round(species.max_health * GrowthRules.stage_multiplier(growth_stage, "hp")))
	bite_damage = int(round(species.bite_damage * GrowthRules.stage_multiplier(growth_stage, "dmg")))
	walk_speed = species.walk_speed * GrowthRules.stage_multiplier(growth_stage, "spd") * 0.8
	run_speed = species.run_speed * GrowthRules.stage_multiplier(growth_stage, "spd") * 0.8
	attack_cooldown = species.bite_cooldown
	current_size = species.size * GrowthRules.stage_multiplier(growth_stage, "size")
	dino_visual.set_size(current_size)


## 注入 Vitals 速率：AI 无体力，故体力相关速率置 0，且口渴归零不结算掉血（与原实现一致）
func _vitals_rates() -> Dictionary:
	return {
		"hunger_interval": HUNGER_INTERVAL,
		"thirst_interval": THIRST_INTERVAL,
		"thirst_sprint_mult": 1.0,
		"stamina_drain": 0.0,
		"stamina_regen": 0.0,
		"stamina_lock": 0.0,
		"drag_stamina_mult": 1.0,
		"drink_rate": DRINK_RATE,
		"starve_interval": STARVE_INTERVAL,
		"starve_damage": STARVE_DAMAGE,
		"thirst_starve_interval": 0.0,
		"thirst_starve_damage": 0,
		"eat_meat_hunger": AI_MEAT_HUNGER,
		"eat_plant_hunger": AI_PLANT_HUNGER,
		"eat_plant_thirst": 0,
		"eat_egg_hunger": EGG_BITE_HUNGER,
		"survival_step_once": true,
	}


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	# 领地登记:落位最终位置由生成方在 add_child 之后设置,_ready 时还未落位,
	# 故延迟到首个物理帧以"现有落位最终位置"为家
	if not _home_recorded:
		_home_recorded = true
		_record_home()
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	decision_timer += delta
	if decision_timer >= DECISION_INTERVAL:
		decision_timer = 0.0
		_decide()

	_act(delta)

	if attack_timer > 0.0:
		attack_timer -= delta
	if _attack_anim_timer > 0.0:
		_attack_anim_timer -= delta
	if lay_cooldown_timer > 0.0:
		lay_cooldown_timer -= delta

	_update_vitals(delta)
	_clamp_to_map()
	dino_visual.play_locomotion(velocity.length() > 0.5, velocity.length() / maxf(run_speed, 0.001))
	move_and_slide()


# ================= 决策 =================
func _decide() -> void:
	# 仇恨最优先:受击后的报复窗口内,无视过饥/过渴等常规优先级,只按体型规则打或跑(肉食/草食通用)
	if _aggro_target != null:
		_aggro_timer -= DECISION_INTERVAL
		var target_valid: bool = is_instance_valid(_aggro_target) and not _target_is_dead(_aggro_target)
		if not target_valid or _aggro_timer <= 0.0:
			# 超时或目标已死/已释放:清空仇恨,掉回常规决策
			_clear_aggro()
		elif _can_beat_attacker(_aggro_target):
			# 攻击者体型 ≤ 自己×0.9 → 打得过,反击
			hunt_target = _aggro_target
			state_controller.transition_to(StateController.State.HUNT)
			return
		else:
			# 打不过 → 逃跑
			flee_target = _aggro_target
			state_controller.transition_to(StateController.State.FLEE)
			return
	# 领地防御(与仇恨互斥:仍有报复目标时跳过;本函数每 DECISION_INTERVAL 才跑一次,
	# 侵入扫描天然并入 0.25s 决策节流,不逐帧扫组)
	if _aggro_target == null and _has_home:
		var intruder: Node3D = _find_home_intruder()
		if intruder != null:
			if species.diet == DinoSpecies.Diet.CARNIVORE:
				# 肉食成年:闯入 [home 25m] 且打得过的,咬
				hunt_target = intruder
				state_controller.transition_to(StateController.State.HUNT)
			else:
				# 草食:肉食者逼近 [home 12m],抢在被动感知之前先逃
				flee_target = intruder
				state_controller.transition_to(StateController.State.FLEE)
			return
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
		if current_thirst < 35:
			# 仅在口渴阈值触发时才扫描水源，并把结果缓存到本决策周期
			_cached_water = _nearest_water()
			if _cached_water != null:
				state_controller.transition_to(StateController.State.DRINK)
				return
		# 繁殖判定挂在漫游决策层（_decide 每 0.25s 一次，巢穴/蛋数扫描天然节流）
		_try_lay_egg()
		state_controller.transition_to(StateController.State.WANDER)
	else:
		if current_hunger < 55:
			# 仅在饥饿阈值触发时才扫描植物，并把结果缓存到本决策周期
			_cached_plant = _nearest_plant()
			if _cached_plant != null:
				state_controller.transition_to(StateController.State.GRAZE)
				return
		if current_thirst < 35:
			_cached_water = _nearest_water()
			if _cached_water != null:
				state_controller.transition_to(StateController.State.DRINK)
				return
		# 繁殖判定挂在漫游决策层（_decide 每 0.25s 一次，巢穴/蛋数扫描天然节流）
		_try_lay_egg()
		state_controller.transition_to(StateController.State.WANDER)


func _prey_weak(prey: Node3D) -> bool:
	if prey is PlayerDino:
		return CombatRules.is_weak_prey((prey as PlayerDino).get_size(), current_size)
	if prey is AIDino:
		return CombatRules.is_weak_prey((prey as AIDino).current_size, current_size)
	return false


## 清空仇恨状态
func _clear_aggro() -> void:
	_aggro_target = null
	_aggro_timer = 0.0


# ================= 领地 =================
## 领地登记:成年 AI(成长阶段 ≥1)以落位最终位置为家盘踞一地;
## Boss(满级霸王龙)全域巡游不设领地,幼体(<1)无领地
func _record_home() -> void:
	if growth_stage < 1 or _is_boss():
		return
	_home_pos = global_position
	_has_home = true


## Boss 判定:满级霸王龙(传说霸主由 EcosystemDirector._spawn_boss 以 MAX_STAGE 阶段生成)
func _is_boss() -> bool:
	return species.id == DinoSpecies.ID_TREX and growth_stage >= DinoSpecies.MAX_STAGE


## 家园侵入者检查(仅由 _decide 调用,天然 0.25s 决策节流,不逐帧扫组):
## - 肉食(有领地者必为成年):玩家或 AI 进入 [home 25m] 且打得过
##   (复用 _can_beat_attacker 的 ×0.9 体型阈值)→ 返回,进 HUNT;打不过不设防,交给常规威胁检查兜底
## - 草食:肉食个体(玩家或 AI)进入 [home 12m] → 返回,提前 FLEE;同类草食串门不算侵入
func _find_home_intruder() -> Node3D:
	var carnivore: bool = species.diet == DinoSpecies.Diet.CARNIVORE
	var best_d: float = HOME_DEFENSE_RADIUS if carnivore else HOME_FLEE_RADIUS
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group(Groups.AI):
		if n == self or not is_instance_valid(n):
			continue
		var other: AIDino = n as AIDino
		if other.is_dead or (not carnivore and other.species.diet != DinoSpecies.Diet.CARNIVORE):
			continue
		var d: float = _home_pos.distance_to(other.global_position)
		var hostile: bool = (not carnivore) or _can_beat_attacker(other)
		if d < best_d and hostile:
			best_d = d
			best = other
	var p: PlayerDino = _player()
	if p != null and not p.is_dead and (carnivore or p.is_carnivore()):
		var d: float = _home_pos.distance_to(p.global_position)
		var hostile: bool = (not carnivore) or _can_beat_attacker(p)
		if d < best_d and hostile:
			best = p
	return best


## 目标是否已死亡(尸体等其他类型不算)
func _target_is_dead(target: Node3D) -> bool:
	if target is AIDino:
		return (target as AIDino).is_dead
	if target is PlayerDino:
		return (target as PlayerDino).is_dead
	return false


## 仇恨体型规则(CombatRules 的 ×0.9):攻击者体型 ≤ 自己×0.9 视为打得过,可反击
func _can_beat_attacker(attacker: Node3D) -> bool:
	var a_size: float = 0.0
	if attacker is PlayerDino:
		a_size = (attacker as PlayerDino).get_size()
	elif attacker is AIDino:
		a_size = (attacker as AIDino).current_size
	return CombatRules.can_counter(a_size, current_size)


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
			# 领地游荡偏向:有家的个体目标点取 home 半径 40m 内——
			# 跑出领地边缘即调头回家,否则照常在家附近随机踱步,个体天然盘踞一地
			if _has_home:
				var to_home: Vector3 = _home_pos - global_position
				to_home.y = 0.0
				if to_home.length() > HOME_WANDER_RADIUS:
					wander_dir = to_home.normalized()
			# 草食龙：向同伴群中心轻微偏移，形成兽群
			if species.diet == DinoSpecies.Diet.HERBIVORE:
				var herd: Vector3 = _herd_center()
				if herd != Vector3.ZERO:
					wander_dir = wander_dir.lerp(herd - global_position, 0.4).normalized()
			wander_timer = 2.5 + randf() * 2.0
	_apply_movement(wander_dir, walk_speed, delta)


func _hunt(delta: float) -> void:
	# 入口校验死亡：玩家死亡后有 3.5 秒尸体展示期，期间 target 仍有效但 is_dead，
	# 若不拦截会持续空咬；直接放弃目标回漫游
	if hunt_target == null or not is_instance_valid(hunt_target) or _target_is_dead(hunt_target):
		hunt_target = null
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
		# 攻击表现:命中即播放撕咬/前扑动画(同一目标 1s 内不重复)
		_play_attack_anim(hunt_target)
		if hunt_target is PlayerDino:
			(hunt_target as PlayerDino).take_damage(_effective_bite(), self)
		elif hunt_target is AIDino:
			(hunt_target as AIDino).take_damage(_effective_bite(), false, self)
		elif hunt_target is AICorpse:
			if (hunt_target as AICorpse).try_eat():
				_eat("meat", AI_MEAT_HEAL)
			else:
				# 尸体已空/淡出中:放弃猎物回漫游,不再原地空咬
				hunt_target = null
				state_controller.transition_to(StateController.State.WANDER)
		elif hunt_target is DinoEgg:
			# 掠食者偷蛋:血量 2 口,每口小收益,蛋破即消失(AI 蛋不再孵化,玩家蛋被偷则失去重生锚点)
			var egg: DinoEgg = hunt_target as DinoEgg
			egg.take_damage(1, self)
			_eat("egg", EGG_BITE_HEAL)
			if egg.hp <= 0:
				hunt_target = null
				state_controller.transition_to(StateController.State.WANDER)


## 攻击动画节流:同一目标 1 秒内不重复触发;切换目标则立即触发
func _play_attack_anim(target: Node) -> void:
	if target == _attack_anim_target and _attack_anim_timer > 0.0:
		return
	_attack_anim_target = target
	_attack_anim_timer = ATTACK_ANIM_THROTTLE
	dino_visual.play_attack()


func _graze(delta: float) -> void:
	# 消费决策周期缓存的植物目标；目标被吃掉/移除时优雅退回漫游，
	# 不立刻重扫全组，等下一个决策周期再刷新
	if _cached_plant == null or not is_instance_valid(_cached_plant):
		_cached_plant = null
		_wander(delta)
		return
	var to: Vector3 = _cached_plant.global_position - global_position
	to.y = 0.0
	if to.length() > GRAZE_RANGE:
		_apply_movement(to.normalized(), walk_speed, delta)
	# 实际进食由 Foliage 的 body_entered 自动触发 on_eat_plant()


func _drink(delta: float) -> void:
	# 消费决策周期缓存的水源目标；水源被移除时优雅退回漫游，
	# 不立刻重扫全组，等下一个决策周期再刷新
	if _cached_water == null or not is_instance_valid(_cached_water):
		_cached_water = null
		_wander(delta)
		return
	var to: Vector2 = Vector2(_cached_water.global_position.x - global_position.x, _cached_water.global_position.z - global_position.z)
	if to.length() > _cached_water.radius - 1.0:
		_apply_movement(Vector3(to.x, 0.0, to.y).normalized(), walk_speed, delta)
	else:
		# 小数部分由 Vitals 累加，满 1 点才回复口渴
		_vitals.drink(delta)
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
	# AI 不冲刺、无体力，只结算饥饿 / 口渴与饿死伤害
	_vitals.tick_survival(delta, false)
	var starve_damage: int = _vitals.pull_starve_damage()
	if starve_damage > 0:
		take_damage(starve_damage, false)


func _eat(kind: String, heal_amt: int) -> void:
	if is_dead:
		return
	_vitals.eat(kind)
	current_health = mini(current_health + heal_amt, max_health)


# 草食 AI 被植物碰到时调用（由 Foliage 触发）
func on_eat_plant() -> void:
	_eat("plant", AI_PLANT_HEAL)


# ================= 繁殖（产蛋） =================
## 繁殖判定：仅在 GRAZE/WANDER 决策层调用（由 _decide 每 0.25s 触发一次，
## 巢穴/蛋数扫描天然节流，不逐帧扫组）。条件齐备即在脚下产蛋，
## 蛋实例经 egg_laid 信号交 Main 挂树，AI 不持有 Main 引用。
func _try_lay_egg() -> void:
	if lay_cooldown_timer > 0.0:
		return
	if current_hunger <= LAY_HUNGER_MIN or growth_stage < LAY_STAGE_MIN:
		return
	if get_tree().get_nodes_in_group(Groups.EGG).size() >= LAY_MAX_EGGS:
		return
	if _nearest_nest_distance() > LAY_NEST_RADIUS:
		return
	lay_cooldown_timer = LAY_COOLDOWN
	var egg := EGG_SCENE.instantiate() as DinoEgg
	egg.species_id = species.id
	egg.owner_player = false
	# 放脚下：蛋尚未入树，直接设局部位置（dynamic 容器为原点恒等变换，局部即世界坐标）
	egg.position = global_position
	# 记录自己的蛋：_find_prey 在 6 秒保护期/3m 巢边范围内会排除它，避免自产自食
	_last_egg = egg
	_last_egg_time = float(Time.get_ticks_msec()) * 0.001
	egg_laid.emit(egg)


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


# ================= 受伤 / 死亡 =================
func take_damage(amount: int, by_player: bool, attacker: Node = null) -> void:
	if is_dead:
		return
	last_by_player = by_player
	# 受击仇恨:有效攻击者(非自身、非环境伤害) → 记入报复窗口,由 _decide 最优先消费
	if attacker != null and attacker != self and is_instance_valid(attacker) and attacker is Node3D:
		_aggro_target = attacker as Node3D
		_aggro_timer = AGGRO_DURATION
	var dmg: int = amount
	if species.passive == DinoSpecies.PassiveAbility.DEFENSE:
		dmg = CombatRules.apply_defense(amount)
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
	# 基础伤害已含成长倍率，故 growth_mult 传 1.0；集群同伴在 14m 内 +20%
	var pack_bonus: float = 0.0
	if species.passive == DinoSpecies.PassiveAbility.PACK and _has_ally_near():
		pack_bonus = CombatRules.PACK_DMG_BONUS
	return CombatRules.bite_damage(bite_damage, 1.0, false, pack_bonus)


func _has_ally_near() -> bool:
	for n in get_tree().get_nodes_in_group(Groups.AI):
		if n != self and is_instance_valid(n) and not (n as AIDino).is_dead and (n as AIDino).species.id == species.id:
			if global_position.distance_to((n as AIDino).global_position) <= 14.0:
				return true
	return false


# ================= 查询 =================
func _player() -> PlayerDino:
	var arr: Array = get_tree().get_nodes_in_group(Groups.PLAYER)
	if arr.is_empty():
		return null
	return arr[0] as PlayerDino

func _find_threat() -> Node3D:
	# APEX 威压：非 APEX 恐龙会被附近的霸王龙(APEX)吓退，无视体型大小
	if species.passive != DinoSpecies.PassiveAbility.APEX:
		var apex: Node3D = _find_apex_threat()
		if apex != null:
			return apex
	var best: Node3D = null
	var best_d: float = FLEE_RADIUS
	for n in get_tree().get_nodes_in_group(Groups.AI):
		if n == self or not is_instance_valid(n):
			continue
		var other: AIDino = n as AIDino
		if other.is_dead or other.species.diet != DinoSpecies.Diet.CARNIVORE:
			continue
		if not CombatRules.is_threat(other.current_size, current_size):
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	var p: PlayerDino = _player()
	if p != null and not p.is_dead and p.is_carnivore() and CombatRules.is_threat(p.get_size(), current_size):
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
	return best


## 在群体与玩家中寻找带 APEX 被动的存活者，返回半径内最近者（威压来源）
func _find_apex_threat() -> Node3D:
	var best: Node3D = null
	var best_d: float = APEX_RADIUS
	for n in get_tree().get_nodes_in_group(Groups.AI):
		if n == self or not is_instance_valid(n):
			continue
		var other: AIDino = n as AIDino
		if other.is_dead or other.species.passive != DinoSpecies.PassiveAbility.APEX:
			continue
		var d: float = global_position.distance_to(other.global_position)
		if d < best_d:
			best_d = d
			best = other
	var p: PlayerDino = _player()
	if p != null and not p.is_dead and p.species.passive == DinoSpecies.PassiveAbility.APEX:
		var d: float = global_position.distance_to(p.global_position)
		if d < best_d:
			best = p
	return best

func _find_prey() -> Node3D:
	var best: Node3D = null
	var best_d: float = SENSE_RADIUS
	for n in get_tree().get_nodes_in_group(Groups.AI):
		if n == self or not is_instance_valid(n):
			continue
		var other: AIDino = n as AIDino
		if other.is_dead:
			continue
		var edible: bool = CombatRules.can_hunt(
				current_size, other.current_size, species.diet, other.species.diet)
		if edible:
			var d: float = global_position.distance_to(other.global_position)
			if d < best_d:
				best_d = d
				best = other
	for c in get_tree().get_nodes_in_group(Groups.CORPSE):
		if is_instance_valid(c):
			var d: float = global_position.distance_to((c as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = c as Node3D
	# 掠食者偷蛋:饿着肚子的肉食龙也盯上蛋(孵化前下口,含玩家巢边的蛋——护巢有理)
	# 但排除自己刚产的蛋与巢边的蛋:蛋就落在脚下 0.5m,不排除会导致饥饿 56~64 时
	# 下一个决策立刻咬掉自己的蛋;3m 内一律不咬同时避免同巢个体互食
	var now: float = float(Time.get_ticks_msec()) * 0.001
	for e in get_tree().get_nodes_in_group(Groups.EGG):
		if not is_instance_valid(e):
			continue
		var egg: DinoEgg = e as DinoEgg
		if egg == null:
			continue
		if _last_egg != null and is_instance_valid(_last_egg) and egg == _last_egg and now - _last_egg_time < OWN_EGG_SAFE_TIME:
			continue
		var d: float = global_position.distance_to(egg.global_position)
		if d <= OWN_EGG_SAFE_RADIUS:
			continue
		if d < best_d:
			best_d = d
			best = egg
	var p: PlayerDino = _player()
	if p != null and not p.is_dead:
		var player_diet: int = DinoSpecies.Diet.CARNIVORE if p.is_carnivore() else DinoSpecies.Diet.HERBIVORE
		var edible: bool = CombatRules.can_hunt(current_size, p.get_size(), species.diet, player_diet)
		if edible:
			var d: float = global_position.distance_to(p.global_position)
			if d < best_d:
				best = p
	return best

func _nearest_plant() -> Node3D:
	var best: Node3D = null
	var best_d: float = SENSE_RADIUS
	for n in get_tree().get_nodes_in_group(Groups.PLANT):
		if is_instance_valid(n):
			var d: float = global_position.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
	return best

func _nearest_water() -> WaterSource:
	var best: WaterSource = null
	var best_d: float = SENSE_RADIUS
	for n in get_tree().get_nodes_in_group(Groups.WATER):
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
	for n in get_tree().get_nodes_in_group(Groups.AI):
		if n != self and is_instance_valid(n):
			var other: AIDino = n as AIDino
			if not other.is_dead and other.species.id == species.id and global_position.distance_to(other.global_position) < 30.0:
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
