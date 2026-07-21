extends Node3D
## 主场景控制器：选种 → 生成世界（扩图 + 湖泊 + 植物 + 生态恐龙 + 玩家）→ 生存计分 → 死亡续关
## 设计要点（对照《诅咒之岛》）：
## - 开局选物种；死亡保留成长、代际+1，下一局接着变强（可存档一直升级）
## - 地图扩大到 160×160，含湖泊水源、干旱生物群系、散布植被
## - 生态由多物种恐龙构成真实食物链，并随玩家成长出现更强掠食者

const PlayerScene: PackedScene = preload("res://scenes/PlayerDino.tscn")
const AIScene: PackedScene = preload("res://scenes/AIDino.tscn")
const CorpseScene: PackedScene = preload("res://scenes/AICorpse.tscn")
const WaterScene: PackedScene = preload("res://scenes/WaterSource.tscn")
const FoliageSpawnerScene: PackedScene = preload("res://scenes/FoliageSpawner.tscn")
const ResourcePointScene: PackedScene = preload("res://scenes/ResourcePoint.tscn")
const HUDScene: PackedScene = preload("res://scenes/HUD.tscn")
const TouchControlsScene: PackedScene = preload("res://scenes/TouchControls.tscn")
const SpeciesSelectScene: PackedScene = preload("res://scenes/SpeciesSelect.tscn")

# 环境音（程序化合成风声，循环）
const SFX_AMBIENT := preload("res://assets/audio/ambient.wav")

# 首次启动是否跳过选种界面（交付时必须为 false，让玩家先选物种）
static var skip_select: bool = false

const MAP_RADIUS: float = 135.0
# 多个水源：主湖 + 两处池塘，分散在大地图上
const WATER_POINTS: Array = [
	Vector3(-45.0, 0.0, 45.0),   # 主湖
	Vector3(70.0, 0.0, -55.0),   # 东池塘
	Vector3(-80.0, 0.0, -70.0),  # 西南池塘
]
const LAKE_RADIUS: float = 18.0
const PLAYER_SPAWN: Vector3 = Vector3(0.0, 1.5, 0.0)
const TARGET_POP: int = 12
const RESPAWN_CHECK: float = 12.0

var player: PlayerDino
var ai_dinos: Array[AIDino] = []
var dynamic: Node3D
var hud: HUD
var touch_controls: TouchControls
var species_select: SpeciesSelect

var kill_count: int = 0
var survival_time: float = 0.0
var score_timer: float = 0.0
var pop_timer: float = 0.0
var is_over: bool = false
var boss_ai: AIDino = null
var boss_respawn_timer: float = 0.0

# 昼夜循环
var sun_light: DirectionalLight3D
var world_env: WorldEnvironment
var day_t: float = 0.3
const DAY_LENGTH: float = 120.0

# 装饰材质（一次性创建）
var mat_trunk: StandardMaterial3D
var mat_foliage: StandardMaterial3D
var mat_rock: StandardMaterial3D


func _ready() -> void:
	randomize()
	dynamic = $Dynamic
	sun_light = $DirectionalLight3D
	world_env = $WorldEnvironment
	mat_trunk = StandardMaterial3D.new()
	mat_trunk.albedo_color = Color(0.4, 0.25, 0.15)
	mat_trunk.roughness = 0.9
	mat_foliage = StandardMaterial3D.new()
	mat_foliage.albedo_color = Color(0.2, 0.45, 0.18)
	mat_foliage.roughness = 0.85
	mat_rock = StandardMaterial3D.new()
	mat_rock.albedo_color = Color(0.5, 0.5, 0.52)
	mat_rock.roughness = 0.95

	# 环境风声（循环）
	var amb := AudioStreamPlayer.new()
	amb.stream = SFX_AMBIENT
	amb.volume_db = -14.0
	add_child(amb)
	amb.play()

	if not skip_select:
		_show_species_select()
	else:
		skip_select = false
		_continue_game()


func _show_species_select() -> void:
	species_select = SpeciesSelectScene.instantiate() as SpeciesSelect
	dynamic.add_child(species_select)
	species_select.selected.connect(_on_species_selected)


func _on_species_selected(species_id: String, is_continue: bool) -> void:
	if species_select != null:
		species_select.queue_free()
		species_select = null
	_start_game(species_id, is_continue)


func _continue_game() -> void:
	var d: Dictionary = SaveManager.load_save()
	var sid: String = d.get("species_id", "raptor")
	_start_game(sid, true)


func _start_game(species_id: String, is_continue: bool) -> void:
	var d: Dictionary = SaveManager.load_save()
	var stage: int = 0
	var gen: int = 1
	if is_continue and d.has("species_id"):
		species_id = d["species_id"]
		stage = d.get("growth_stage", 0)
		gen = d.get("generation", 1)
	else:
		d["species_id"] = species_id
		d["growth_stage"] = 0
		d["generation"] = 1
		SaveManager.write_save(d)
		gen = 1

	kill_count = 0
	survival_time = 0.0
	is_over = false

	_spawn_water()
	_spawn_foliage()
	_spawn_decor()
	_spawn_resource_points()
	_spawn_hud()
	_spawn_player(species_id, stage, gen)
	_spawn_ecosystem(stage)
	_spawn_touch_controls()

	hud.show_hint("管理好饥饿/口渴/体力。靠近湖泊按 E 或饮水键喝水，吃对的食物会成长。")
	hud.show_help()


# ================= 生成 =================
func _spawn_water() -> void:
	var radii := [LAKE_RADIUS, 12.0, 10.0]
	for i in WATER_POINTS.size():
		var w: WaterSource = WaterScene.instantiate() as WaterSource
		w.global_position = WATER_POINTS[i]
		w.radius = radii[i] if i < radii.size() else 10.0
		dynamic.add_child(w)


func _spawn_foliage() -> void:
	var fs: FoliageSpawner = FoliageSpawnerScene.instantiate() as FoliageSpawner
	dynamic.add_child(fs)


func _spawn_resource_points() -> void:
	# 巢穴与矿物盐散布在地图各处（避开水源与出生点）
	var nests := [Vector3(45.0, 0.0, 50.0), Vector3(-60.0, 0.0, 30.0), Vector3(20.0, 0.0, -70.0)]
	var licks := [Vector3(-30.0, 0.0, -40.0), Vector3(80.0, 0.0, 20.0), Vector3(-90.0, 0.0, -30.0)]
	for pos in nests:
		var rp: ResourcePoint = ResourcePointScene.instantiate() as ResourcePoint
		rp.point_type = ResourcePoint.Type.NEST
		rp.global_position = pos
		dynamic.add_child(rp)
	for pos in licks:
		var rp: ResourcePoint = ResourcePointScene.instantiate() as ResourcePoint
		rp.point_type = ResourcePoint.Type.LICK
		rp.global_position = pos
		dynamic.add_child(rp)


func _spawn_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in 34:
		var pos: Vector3 = _random_ground_pos()
		if _too_close_to_water(pos, 4.0) or pos.distance_to(PLAYER_SPAWN) < 12.0:
			continue
		dynamic.add_child(_make_tree(pos))
	for i in 22:
		var pos: Vector3 = _random_ground_pos()
		if _too_close_to_water(pos, 4.0) or pos.distance_to(PLAYER_SPAWN) < 10.0:
			continue
		dynamic.add_child(_make_rock(pos))
	# 树林集群：3 处聚拢的树群，丰富地貌
	for c in 3:
		var center: Vector3 = _random_ground_pos()
		if _too_close_to_water(center, 8.0):
			continue
		for k in range(rng.randi_range(5, 8)):
			var off := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			var p: Vector3 = center + off
			if _too_close_to_water(p, 4.0):
				continue
			dynamic.add_child(_make_tree(p))


## 是否过于靠近任一水源（避免装饰/植物长在水里）
func _too_close_to_water(pos: Vector3, margin: float) -> bool:
	var radii := [LAKE_RADIUS, 12.0, 10.0]
	for i in WATER_POINTS.size():
		var r: float = radii[i] if i < radii.size() else 10.0
		if pos.distance_to(WATER_POINTS[i]) < r + margin:
			return true
	return false


func _make_tree(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var trunk := CSGCylinder3D.new()
	trunk.radius = 0.4
	trunk.height = 3.0
	trunk.position = Vector3(0, 1.5, 0)
	trunk.use_collision = true
	trunk.material = mat_trunk
	n.add_child(trunk)
	var top := CSGSphere3D.new()
	top.radius = 1.4
	top.position = Vector3(0, 3.5, 0)
	top.use_collision = true
	top.material = mat_foliage
	n.add_child(top)
	return n


func _make_rock(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	var r := CSGBox3D.new()
	var s: float = randf_range(1.0, 1.8)
	r.size = Vector3(s, s * 0.7, s * 1.1)
	r.position = Vector3(0, 0.5, 0)
	r.use_collision = true
	r.material = mat_rock
	n.add_child(r)
	return n


func _spawn_player(species_id: String, stage: int, gen: int) -> void:
	player = PlayerScene.instantiate() as PlayerDino
	player.species_id = species_id
	player.start_growth_stage = stage
	player.generation = gen
	player.map_radius = MAP_RADIUS
	# 先连信号，再加树（_ready 内会发出初始信号）
	player.health_changed.connect(_on_player_health_changed)
	player.hunger_changed.connect(_on_player_hunger_changed)
	player.thirst_changed.connect(_on_player_thirst_changed)
	player.stamina_changed.connect(_on_player_stamina_changed)
	player.growth_changed.connect(_on_player_growth_changed)
	player.banner.connect(_on_player_banner)
	player.hint.connect(_on_player_hint)
	player.died.connect(_on_player_died)
	dynamic.add_child(player)
	player.global_position = PLAYER_SPAWN


func _spawn_ecosystem(player_stage: int) -> void:
	var roster := _build_roster(player_stage)
	for sid in roster:
		_spawn_ai(sid, _random_ai_stage(player_stage))
	_spawn_boss()


## 传说霸主：地图上持续游荡的顶级霸王龙（最高成长阶段），作为世界级威胁
func _spawn_boss() -> void:
	var ai: AIDino = AIScene.instantiate() as AIDino
	ai.species_id = "trex"
	ai.start_growth_stage = DinoSpecies.MAX_STAGE
	ai.map_radius = MAP_RADIUS
	var ang: float = randf() * TAU
	var pos: Vector3 = Vector3(sin(ang), 0.0, cos(ang)) * (MAP_RADIUS - 20.0)
	ai.global_position = Vector3(pos.x, 1.5, pos.z)
	ai.died.connect(_on_ai_died)
	dynamic.add_child(ai)
	ai_dinos.append(ai)
	boss_ai = ai
	hud.show_banner("传说霸主 · 霸王龙出没！")


func _build_roster(player_stage: int) -> Array[String]:
	var roster: Array[String] = ["galli", "galli", "galli", "trike", "trike", "anky", "anky", "raptor", "raptor", "raptor", "carno"]
	if player_stage >= 1:
		roster.append("carno")
	if player_stage >= 2:
		roster.append("trex")
	if player_stage >= 3:
		roster.append("trex")
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
	ai.map_radius = MAP_RADIUS
	var pos: Vector3 = _random_ground_pos()
	# 不要紧贴玩家出生点
	if pos.distance_to(PLAYER_SPAWN) < 14.0:
		pos = pos.normalized() * 30.0 if pos.length() > 0.1 else Vector3(30, 0, 0)
	dynamic.add_child(ai)
	ai.global_position = Vector3(pos.x, 1.5, pos.z)
	ai.died.connect(_on_ai_died)
	ai_dinos.append(ai)


# ================= HUD / 触屏 =================
func _spawn_hud() -> void:
	hud = HUDScene.instantiate() as HUD
	dynamic.add_child(hud)
	hud.menu_pressed.connect(_on_menu)


func _spawn_touch_controls() -> void:
	touch_controls = TouchControlsScene.instantiate() as TouchControls
	dynamic.add_child(touch_controls)
	touch_controls.move_input_changed.connect(player.set_move_input)
	touch_controls.bite_pressed.connect(player.try_bite)
	touch_controls.jump_pressed.connect(player.try_jump)
	touch_controls.ability_pressed.connect(player.try_ability)
	touch_controls.drink_pressed.connect(player.set_drink_held)
	touch_controls.look_input_changed.connect(player.add_look_delta)
	touch_controls.camera_pressed.connect(player.cycle_camera_mode)
	player.camera_mode_changed.connect(func(n: String): hud.show_hint("视角：" + n))
	if player != null and is_instance_valid(player):
		touch_controls.set_ability_visible(player.has_charge_ability())


# ================= 信号 =================
func _on_player_health_changed(c: int, m: int) -> void:
	hud.set_health(c, m)

func _on_player_hunger_changed(c: int, m: int) -> void:
	hud.set_hunger(c, m)

func _on_player_thirst_changed(c: int, m: int) -> void:
	hud.set_thirst(c, m)

func _on_player_stamina_changed(c: int, m: int) -> void:
	hud.set_stamina(c, m)

func _on_player_growth_changed(stage: int, name: String, progress: float) -> void:
	hud.set_growth(stage, name, progress)
	if player != null:
		hud.set_species(player.species.name, player.species.diet_text(), name)

func _on_player_banner(text: String) -> void:
	hud.show_banner(text)

func _on_player_hint(text: String) -> void:
	if text == "":
		hud.hide_hint()
	else:
		hud.show_hint(text)

func _on_player_died() -> void:
	if is_over:
		return
	is_over = true
	# 存档：保留成长，代际 +1，记录最佳成绩
	var d: Dictionary = SaveManager.load_save()
	d["species_id"] = player.species.id
	d["growth_stage"] = player.growth_stage
	d["generation"] = player.generation + 1
	d["best_time"] = maxi(d.get("best_time", 0), int(survival_time))
	d["best_kills"] = maxi(d.get("best_kills", 0), kill_count)
	SaveManager.write_save(d)
	var best: String = "最佳存活 %d 秒 / 最多击杀 %d" % [d.get("best_time", 0), d.get("best_kills", 0)]
	hud.show_death("你被猎杀了！\n第 %d 代 · 存活 %d 秒 · 击杀 %d\n成长已保留，下一局继续变强\n%s" % [player.generation, int(survival_time), kill_count, best])
	await get_tree().create_timer(3.5).timeout
	skip_select = true
	get_tree().reload_current_scene()


func _on_ai_died(ai: AIDino, by_player: bool) -> void:
	ai_dinos.erase(ai)
	if ai == boss_ai:
		boss_ai = null
		boss_respawn_timer = 60.0
	# 生成尸体（按死亡物种上色）
	var corpse: AICorpse = CorpseScene.instantiate() as AICorpse
	corpse.species_id = ai.species.id
	corpse.species_colors = [ai.species.body_color, ai.species.dark_color]
	dynamic.add_child(corpse)
	corpse.global_position = ai.global_position
	if by_player:
		kill_count += 1


func _on_menu() -> void:
	skip_select = false
	get_tree().reload_current_scene()


# ================= 主循环 =================
func _process(delta: float) -> void:
	if is_over:
		return
	survival_time += delta
	# 昼夜循环
	day_t = fmod(day_t + delta / DAY_LENGTH, 1.0)
	_apply_day_night()
	# 生态维护：数量不足时在边缘补充
	pop_timer += delta
	if pop_timer >= RESPAWN_CHECK:
		pop_timer = 0.0
		if ai_dinos.size() < TARGET_POP:
			var sid: String = "galli" if randf() < 0.5 else "raptor"
			_spawn_ai(sid, _random_ai_stage(player.growth_stage if player != null else 0))
	# 传说霸主重生
	if boss_ai == null and boss_respawn_timer > 0.0:
		boss_respawn_timer -= delta
		if boss_respawn_timer <= 0.0:
			_spawn_boss()
	# 计分刷新
	score_timer += delta
	if score_timer >= 0.5:
		score_timer = 0.0
		var gen: int = player.generation if player != null else 1
		hud.set_score(int(survival_time), kill_count, gen)
	# 技能冷却显示（仅冲锋物种）
	if player != null and is_instance_valid(player) and player.has_charge_ability():
		touch_controls.set_ability_cooldown(player.charge_cooldown_timer, PlayerDino.CHARGE_COOLDOWN)


# ================= 工具 =================
func _random_ground_pos() -> Vector3:
	var angle: float = randf() * TAU
	var dist: float = randf() * (MAP_RADIUS - 6.0)
	return Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)


# ================= 昼夜循环 =================
func _apply_day_night() -> void:
	var h: float = sin(day_t * TAU)                 # -1 午夜 .. 1 正午
	var day: float = clampf(h, 0.0, 1.0)            # 0 夜 .. 1 昼
	var twilight: float = clampf(1.0 - abs(h) * 3.0, 0.0, 1.0)  # 近地平线辉光
	if sun_light != null:
		sun_light.light_energy = lerpf(0.15, 1.25, day)
		var day_col := Color(1.0, 0.98, 0.9)
		var dusk_col := Color(1.0, 0.55, 0.3)
		var night_col := Color(0.4, 0.5, 0.8)
		var col := night_col.lerp(day_col, day)
		col = col.lerp(dusk_col, twilight * 0.6)
		sun_light.light_color = col
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment
		var top := Color(0.1, 0.15, 0.35).lerp(Color(0.35, 0.6, 0.85), day)
		var hor := Color(0.2, 0.25, 0.4).lerp(Color(0.7, 0.8, 0.92), day)
		hor = hor.lerp(Color(1.0, 0.5, 0.3), twilight * 0.5)
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm := env.sky.sky_material as ProceduralSkyMaterial
			sm.sky_top_color = top
			sm.sky_horizon_color = hor
		env.ambient_light_energy = lerpf(0.25, 0.7, day)
