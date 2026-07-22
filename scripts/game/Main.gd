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
const MapSelectScene: PackedScene = preload("res://scenes/MapSelect.tscn")

# 环境音（程序化合成风声，循环）
const SFX_AMBIENT := preload("res://assets/audio/ambient.wav")

# 首次启动是否跳过选种界面（交付时必须为 false，让玩家先选物种）
static var skip_select: bool = false

# 地图半径由地形半幅决定（无地形时回退 135）
func _map_radius() -> float:
	return terrain.half_extent - 6.0 if terrain != null else 135.0
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

# 地形生成器（替代旧的 CSG 地板）
var terrain: TerrainGenerator
var _map_def: Maps.MapDef

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


func _ready() -> void:
	randomize()
	dynamic = $Dynamic
	sun_light = $DirectionalLight3D
	world_env = $WorldEnvironment

	# 环境风声（循环）
	var amb := AudioStreamPlayer.new()
	amb.stream = SFX_AMBIENT
	amb.volume_db = -14.0
	add_child(amb)
	amb.play()

	if not skip_select:
		_show_map_select()
	else:
		skip_select = false
		_continue_game()


func _show_species_select() -> void:
	species_select = SpeciesSelectScene.instantiate() as SpeciesSelect
	dynamic.add_child(species_select)
	species_select.selected.connect(_on_species_selected)


func _show_map_select() -> void:
	var ms: MapSelect = MapSelectScene.instantiate() as MapSelect
	dynamic.add_child(ms)
	ms.selected.connect(_on_map_selected)


func _on_map_selected(map_id: String) -> void:
	_map_def = Maps.by_id(map_id)
	_show_species_select()


func _on_species_selected(species_id: String, is_continue: bool) -> void:
	if species_select != null:
		species_select.queue_free()
		species_select = null
	_start_game(species_id, is_continue)


func _continue_game() -> void:
	var d: Dictionary = SaveManager.load_save()
	_map_def = Maps.by_id(d.get("map_id", "forest"))
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
		d["map_id"] = _map_def.id
		SaveManager.write_save(d)
		gen = 1

	kill_count = 0
	survival_time = 0.0
	is_over = false

	_spawn_terrain(_map_def)
	_spawn_water()
	_spawn_foliage()
	_spawn_nature()
	_spawn_resource_points()
	_spawn_hud()
	_spawn_player(species_id, stage, gen)
	_spawn_ecosystem(stage)
	_spawn_touch_controls()

	hud.show_hint("管理好饥饿/口渴/体力。靠近湖泊按 E 或饮水键喝水，吃对的食物会成长。")
	hud.show_help()


# ================= 生成 =================
## 生成地形网格并应用地图的天空/雾基调
func _spawn_terrain(def: Maps.MapDef) -> void:
	terrain = TerrainGenerator.new()
	terrain.setup(def)
	terrain.name = "Terrain"
	dynamic.add_child(terrain)
	_apply_map_atmosphere(def)


## 用地图预设里的天空/雾/环境光基调初始化 WorldEnvironment
func _apply_map_atmosphere(def: Maps.MapDef) -> void:
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = def.fog_density
	env.fog_light_color = def.fog_color


func _spawn_water() -> void:
	var radii := [LAKE_RADIUS, 12.0, 10.0]
	for i in _map_def.water_points.size():
		var wp := _map_def.water_points[i] as Vector3
		var w: WaterSource = WaterScene.instantiate() as WaterSource
		w.global_position = Vector3(wp.x, _map_def.water_level, wp.z)
		w.radius = radii[i] if i < radii.size() else 10.0
		dynamic.add_child(w)


func _spawn_foliage() -> void:
	var fs: FoliageSpawner = FoliageSpawnerScene.instantiate() as FoliageSpawner
	fs.terrain = terrain
	fs.plant_slugs = _map_def.plant_models
	fs.plant_count = _map_def.plant_count
	dynamic.add_child(fs)


func _spawn_resource_points() -> void:
	# 巢穴与矿物盐散布在地图各处（避开水源，按地形高度放置）
	var nests := [Vector3(45.0, 0.0, 50.0), Vector3(-60.0, 0.0, 30.0), Vector3(20.0, 0.0, -70.0)]
	var licks := [Vector3(-30.0, 0.0, -40.0), Vector3(80.0, 0.0, 20.0), Vector3(-90.0, 0.0, -30.0)]
	for pos in nests:
		if terrain != null and terrain.is_under_water(pos.x, pos.z):
			continue
		var rp: ResourcePoint = ResourcePointScene.instantiate() as ResourcePoint
		rp.point_type = ResourcePoint.Type.NEST
		var y: float = terrain.get_height(pos.x, pos.z) if terrain != null else 0.0
		rp.global_position = Vector3(pos.x, y, pos.z)
		dynamic.add_child(rp)
	for pos in licks:
		if terrain != null and terrain.is_under_water(pos.x, pos.z):
			continue
		var rp: ResourcePoint = ResourcePointScene.instantiate() as ResourcePoint
		rp.point_type = ResourcePoint.Type.LICK
		var y: float = terrain.get_height(pos.x, pos.z) if terrain != null else 0.0
		rp.global_position = Vector3(pos.x, y, pos.z)
		dynamic.add_child(rp)


## 在地形上随机撒自然模型（树木 + 岩石），替代旧的 CSG 装饰
func _spawn_nature() -> void:
	if terrain == null:
		return
	var half := terrain.half_extent - 8.0
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	# 树木
	for i in _map_def.tree_count:
		var x: float = rng.randf_range(-half, half)
		var z: float = rng.randf_range(-half, half)
		if terrain.is_under_water(x, z):
			continue
		if abs(x) < 12.0 and abs(z) < 12.0:
			continue  # 出生点附近留空
		var slug: String = _map_def.tree_models[rng.randi() % _map_def.tree_models.size()]
		var s: float = rng.randf_range(0.8, 1.3)
		var p := NatureProp.create(slug, s, 0.0)
		p.global_position = Vector3(x, terrain.get_height(x, z), z)
		dynamic.add_child(p)
	# 岩石
	for i in _map_def.rock_count:
		var x: float = rng.randf_range(-half, half)
		var z: float = rng.randf_range(-half, half)
		if terrain.is_under_water(x, z):
			continue
		if abs(x) < 10.0 and abs(z) < 10.0:
			continue
		var slug: String = _map_def.rock_models[rng.randi() % _map_def.rock_models.size()]
		var s: float = rng.randf_range(0.6, 1.8)
		var p := NatureProp.create(slug, s, 0.0)
		p.global_position = Vector3(x, terrain.get_height(x, z), z)
		dynamic.add_child(p)


func _spawn_player(species_id: String, stage: int, gen: int) -> void:
	player = PlayerScene.instantiate() as PlayerDino
	player.species_id = species_id
	player.start_growth_stage = stage
	player.generation = gen
	player.map_radius = _map_radius()
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
	var py: float = terrain.get_height(PLAYER_SPAWN.x, PLAYER_SPAWN.z) if terrain != null else PLAYER_SPAWN.y
	player.global_position = Vector3(PLAYER_SPAWN.x, py + 0.2, PLAYER_SPAWN.z)


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
	ai.map_radius = _map_radius()
	var ang: float = randf() * TAU
	var pos: Vector3 = Vector3(sin(ang), 0.0, cos(ang)) * (_map_radius() - 20.0)
	var by: float = terrain.get_height(pos.x, pos.z) if terrain != null else 1.5
	ai.global_position = Vector3(pos.x, by + 0.2, pos.z)
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
	ai.map_radius = _map_radius()
	var angle: float = randf() * TAU
	var dist: float = randf() * (_map_radius() - 6.0)
	var pos: Vector3 = Vector3(sin(angle) * dist, 0.0, cos(angle) * dist)
	# 不要紧贴玩家出生点
	if pos.distance_to(PLAYER_SPAWN) < 14.0:
		pos = pos.normalized() * 30.0 if pos.length() > 0.1 else Vector3(30, 0, 0)
	dynamic.add_child(ai)
	var ay: float = terrain.get_height(pos.x, pos.z) if terrain != null else 1.5
	ai.global_position = Vector3(pos.x, ay + 0.2, pos.z)
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


# ================= 昼夜循环 =================
func _apply_day_night() -> void:
	var h: float = sin(day_t * TAU)                 # -1 午夜 .. 1 正午
	var day: float = clampf(h, 0.0, 1.0)            # 0 夜 .. 1 昼
	var twilight: float = clampf(1.0 - abs(h) * 3.0, 0.0, 1.0)  # 近地平线辉光
	# 地图基调（日间基色），未选地图时回退默认
	var day_top := Color(0.35, 0.6, 0.85)
	var day_horizon := Color(0.7, 0.82, 0.9)
	var sun_day := Color(1.0, 0.98, 0.9)
	var fog_base := Color(0.8, 0.85, 0.8)
	if _map_def != null:
		day_top = _map_def.sky_top
		day_horizon = _map_def.sky_horizon
		sun_day = _map_def.sun_color
		fog_base = _map_def.fog_color
	if sun_light != null:
		sun_light.light_energy = lerpf(0.15, 1.25, day)
		var day_col := sun_day
		var dusk_col := Color(1.0, 0.55, 0.3)
		var night_col := Color(0.4, 0.5, 0.8)
		var col := night_col.lerp(day_col, day)
		col = col.lerp(dusk_col, twilight * 0.6)
		sun_light.light_color = col
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment
		var top := Color(0.1, 0.15, 0.35).lerp(day_top, day)
		var hor := Color(0.2, 0.25, 0.4).lerp(day_horizon, day)
		hor = hor.lerp(Color(1.0, 0.5, 0.3), twilight * 0.5)
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm := env.sky.sky_material as ProceduralSkyMaterial
			sm.sky_top_color = top
			sm.sky_horizon_color = hor
		env.ambient_light_energy = lerpf(0.25, 0.7, day)
		# 雾色随昼夜微调（夜间偏暗）
		if env.fog_enabled:
			env.fog_light_color = fog_base.lerp(Color(0.18, 0.22, 0.32), (1.0 - day) * 0.5)
