class_name EcosystemDirector
extends Node
## AI 生态子系统：生成多物种恐龙花名册与传说霸主、维持目标种群数量、
## 管理 Boss 重生倒计时。尸体生成与玩家击杀计数由 Main 编排器处理（经 ai_died 信号广播）。

signal ai_died(ai: AIDino, by_player: bool)
signal boss_spawned

const AIScene: PackedScene = preload("res://scenes/AIDino.tscn")
const TARGET_POP: int = 12
const RESPAWN_CHECK: float = 12.0
const BOSS_RESPAWN_DELAY: float = 60.0

var ai_dinos: Array[AIDino] = []
var boss_ai: AIDino = null
var boss_respawn_timer: float = 0.0
var pop_timer: float = 0.0

var _terrain: TerrainGenerator = null
var _player_spawn: Vector3 = Vector3.ZERO
var _map_radius_getter: Callable = Callable()
var _parent: Node3D = null


## 注入地形、玩家出生点、地图半径查询（Main._map_radius 传 Callable）与动态容器
func setup(terrain: TerrainGenerator, player_spawn: Vector3, map_radius_getter: Callable, parent: Node3D) -> void:
	_terrain = terrain
	_player_spawn = player_spawn
	_map_radius_getter = map_radius_getter
	_parent = parent


## 地形建好后更新引用（选图期间地形尚未生成，Main._ready 时先以 null 注入）
func set_terrain(terrain: TerrainGenerator) -> void:
	_terrain = terrain


## 生成整支生态花名册 + 传说霸主（开局 / 死亡重开时各调用一次）
func spawn_roster(player_stage: int) -> void:
	var roster := _build_roster(player_stage)
	for sid in roster:
		_spawn_ai(sid, _random_ai_stage(player_stage))
	_spawn_boss()


## 生态维护：种群不足时在边缘补充；传说霸主重生倒计时
func maintain_population(delta: float, player_stage: int) -> void:
	pop_timer += delta
	if pop_timer >= RESPAWN_CHECK:
		pop_timer = 0.0
		if ai_dinos.size() < TARGET_POP:
			var sid: String = DinoSpecies.ID_GALLI if randf() < 0.5 else DinoSpecies.ID_RAPTOR
			_spawn_ai(sid, _random_ai_stage(player_stage))
	# 传说霸主重生
	if boss_ai == null and boss_respawn_timer > 0.0:
		boss_respawn_timer -= delta
		if boss_respawn_timer <= 0.0:
			_spawn_boss()


## AI 死亡登记：移出花名册、Boss 死亡则启动重生倒计时，并广播 ai_died
func handle_ai_death(ai: AIDino, by_player: bool) -> void:
	ai_dinos.erase(ai)
	if ai == boss_ai:
		boss_ai = null
		boss_respawn_timer = BOSS_RESPAWN_DELAY
	ai_died.emit(ai, by_player)


## 释放全部 AI（死亡重开时调用；died 信号仅在各自 _die 中手动 emit，queue_free 不会触发副作用）
func clear_all() -> void:
	for ai in ai_dinos:
		ai.queue_free()
	ai_dinos.clear()
	boss_ai = null
	boss_respawn_timer = 0.0
	pop_timer = 0.0


## 传说霸主：地图上持续游荡的顶级霸王龙（最高成长阶段），作为世界级威胁
func _spawn_boss() -> void:
	var ai: AIDino = AIScene.instantiate() as AIDino
	ai.species_id = DinoSpecies.ID_TREX
	ai.start_growth_stage = DinoSpecies.MAX_STAGE
	var radius: float = _map_radius_getter.call()
	ai.map_radius = radius
	var ang: float = randf() * TAU
	var pos: Vector3 = Vector3(sin(ang), 0.0, cos(ang)) * (radius - 20.0)
	var by: float = _terrain.get_height(pos.x, pos.z) if _terrain != null else 1.5
	ai.global_position = Vector3(pos.x, by + 0.2, pos.z)
	ai.died.connect(handle_ai_death)
	_parent.add_child(ai)
	ai_dinos.append(ai)
	boss_ai = ai
	boss_spawned.emit()


func _build_roster(player_stage: int) -> Array[String]:
	var roster: Array[String] = [DinoSpecies.ID_GALLI, DinoSpecies.ID_GALLI, DinoSpecies.ID_GALLI, DinoSpecies.ID_TRIKE, DinoSpecies.ID_TRIKE, DinoSpecies.ID_ANKY, DinoSpecies.ID_ANKY, DinoSpecies.ID_RAPTOR, DinoSpecies.ID_RAPTOR, DinoSpecies.ID_RAPTOR, DinoSpecies.ID_CARNO]
	if player_stage >= 1:
		roster.append(DinoSpecies.ID_CARNO)
	if player_stage >= 2:
		roster.append(DinoSpecies.ID_TREX)
	if player_stage >= 3:
		roster.append(DinoSpecies.ID_TREX)
	return roster


func _random_ai_stage(player_stage: int) -> int:
	var r: float = randf()
	if r < 0.5:
		return 0
	elif r < 0.8:
		return 1
	elif r < 0.95:
		return 2
	return mini(3, player_stage + 1)


func _spawn_ai(species_id: String, stage: int) -> void:
	var ai: AIDino = AIScene.instantiate() as AIDino
	ai.species_id = species_id
	ai.start_growth_stage = stage
	var radius: float = _map_radius_getter.call()
	ai.map_radius = radius
	var angle: float = randf() * TAU
	var dist: float = randf() * (radius - 6.0)
	var pos: Vector3 = Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
	# 不要紧贴玩家出生点
	if pos.distance_to(_player_spawn) < 14.0:
		pos = pos.normalized() * 30.0 if pos.length() > 0.1 else Vector3(30, 0, 0)
	_parent.add_child(ai)
	var ay: float = _terrain.get_height(pos.x, pos.z) if _terrain != null else 1.5
	ai.global_position = Vector3(pos.x, ay + 0.2, pos.z)
	ai.died.connect(handle_ai_death)
	ai_dinos.append(ai)
