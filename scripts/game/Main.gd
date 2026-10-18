extends Node3D
## 主场景编排器：选图 → 选种 → 生成世界（扩图 + 湖泊 + 植物 + 资源点 + 生态恐龙 + 玩家）→ 生存计分 → 死亡续关
## 设计要点（对照《诅咒之岛》）：
## - 开局选物种；死亡保留成长、代际+1，下一局接着变强（可存档一直升级）
## - 本脚本只做流程编排、节点生成与信号接线，子系统拆分为：
##   DayNightCycle（昼夜循环）/ ScoreKeeper（计分）/ WorldBuilder（世界构建）/ EcosystemDirector（AI 生态）

const PlayerScene: PackedScene = preload("res://scenes/PlayerDino.tscn")
const CorpseScene: PackedScene = preload("res://scenes/AICorpse.tscn")
const HUDScene: PackedScene = preload("res://scenes/HUD.tscn")
const TouchControlsScene: PackedScene = preload("res://scenes/TouchControls.tscn")
const SpeciesSelectScene: PackedScene = preload("res://scenes/SpeciesSelect.tscn")
const MapSelectScene: PackedScene = preload("res://scenes/MapSelect.tscn")

# 环境音（程序化合成风声，循环）
const SFX_AMBIENT := preload("res://assets/audio/ambient.wav")

# 首次启动是否跳过选种界面（交付时必须为 false，让玩家先选物种）
static var skip_select: bool = false

const PLAYER_SPAWN: Vector3 = Vector3(0.0, 1.5, 0.0)

var player: PlayerDino
var dynamic: Node3D
var hud: HUD
var touch_controls: TouchControls
var species_select: SpeciesSelect

# 地形生成器（替代旧的 CSG 地板）
var terrain: TerrainGenerator
var _map_def: Maps.MapDef

# 运行期状态
var is_over: bool = false

# 光照与环境节点（仅用于注入 DayNightCycle / WorldBuilder）
var sun_light: DirectionalLight3D
var world_env: WorldEnvironment

# 子系统：昼夜 / 计分 / 世界构建 / AI 生态
var day_night: DayNightCycle
var score_keeper: ScoreKeeper
var world_builder: WorldBuilder
var director: EcosystemDirector


# 地图半径由地形半幅决定（无地形时回退 135）
func _map_radius() -> float:
	return terrain.half_extent - 6.0 if terrain != null else 135.0


func _ready() -> void:
	randomize()
	dynamic = $Dynamic
	sun_light = $DirectionalLight3D
	world_env = $WorldEnvironment

	# 子系统装配（选图期间地形未生成，director 先以 null 地形注入，开局后再更新）
	# 三个 Node 型子系统必须 add_child 挂进场景树：否则 reload_current_scene 释放 Main 时
	# 它们成为孤儿节点无法回收（Node 非引用计数，不挂树必须手动 free）。均无自带回调，挂树零副作用。
	day_night = DayNightCycle.new()
	day_night.setup(sun_light, world_env)
	add_child(day_night)
	score_keeper = ScoreKeeper.new()  # RefCounted，随引用自动释放，无需挂树
	world_builder = WorldBuilder.new()
	add_child(world_builder)
	director = EcosystemDirector.new()
	director.setup(null, PLAYER_SPAWN, _map_radius, dynamic)
	director.ai_died.connect(_on_ai_died)
	director.boss_spawned.connect(_on_boss_spawned)
	add_child(director)

	# 环境风声（循环）
	var amb := AudioStreamPlayer.new()
	amb.stream = SFX_AMBIENT
	amb.volume_db = -14.0
	amb.bus = AudioManager.BUS_AMBIENT
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
	day_night.set_map_def(_map_def)
	_show_species_select()


func _on_species_selected(species_id: String, is_continue: bool) -> void:
	if species_select != null:
		species_select.queue_free()
		species_select = null
	_start_game(species_id, is_continue)


func _continue_game() -> void:
	var d: Dictionary = SaveManager.load_save()
	_map_def = Maps.by_id(d.get("map_id", Maps.DEFAULT_MAP_ID))
	day_night.set_map_def(_map_def)
	var sid: String = d.get("species_id", DinoSpecies.ID_RAPTOR)
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

	score_keeper.reset()
	is_over = false

	# 世界资产（仅首局生成，死亡重开不重建）
	terrain = world_builder.spawn_terrain(dynamic, _map_def, world_env)
	director.set_terrain(terrain)
	world_builder.spawn_water(dynamic, _map_def)
	world_builder.spawn_foliage(dynamic, _map_def, terrain)
	world_builder.spawn_nature(dynamic, _map_def, terrain)
	world_builder.spawn_resource_points(dynamic, terrain)
	# 运行期角色与 UI（顺序：HUD → 玩家 → 生态 → 触屏）
	_spawn_hud()
	_spawn_player(species_id, stage, gen)
	director.spawn_roster(stage)
	_spawn_touch_controls()

	hud.show_hint("管理好饥饿/口渴/体力。靠近湖泊按 E 或饮水键喝水，吃对的食物会成长。")
	hud.show_help()


# ================= 玩家 / HUD / 触屏 =================
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

## 传说霸主登场横幅（由 EcosystemDirector 发出 boss_spawned 时显示）
func _on_boss_spawned() -> void:
	hud.show_banner("传说霸主 · 霸王龙出没！")


func _on_player_died() -> void:
	if is_over:
		return
	is_over = true
	# 存档：保留成长，代际 +1，记录最佳成绩
	var d: Dictionary = SaveManager.load_save()
	d["species_id"] = player.species.id
	d["growth_stage"] = player.growth_stage
	d["generation"] = player.generation + 1
	d["best_time"] = maxi(d.get("best_time", 0), int(score_keeper.survival_time))
	d["best_kills"] = maxi(d.get("best_kills", 0), score_keeper.kill_count)
	SaveManager.write_save(d)
	var best: String = "最佳存活 %d 秒 / 最多击杀 %d" % [d.get("best_time", 0), d.get("best_kills", 0)]
	hud.show_death("你被猎杀了！\n第 %d 代 · 存活 %d 秒 · 击杀 %d\n成长已保留，下一局继续变强\n%s" % [player.generation, int(score_keeper.survival_time), score_keeper.kill_count, best])
	await get_tree().create_timer(3.5).timeout
	# 不整场景重载：地形/植被等世界资产无需重建，移动端可避免死亡后数秒卡顿，仅重置运行期节点
	_restart_run()


## 死亡重开：只释放并重建"运行期"节点（玩家/AI/HUD/触屏/尸体/选图选种残留），
## 保留世界资产（地形、水源、植被、资源点、树石、环境音），成长按存档续代
func _restart_run() -> void:
	# 1) 先释放运行期节点，再重建（全部为 instantiate 新实例，信号连接不会重复）
	if player != null:
		player.queue_free()
		player = null
	# AI（含 boss）交由生态子系统统一释放
	director.clear_all()
	if hud != null:
		hud.queue_free()
		hud = null
	if touch_controls != null:
		touch_controls.queue_free()
		touch_controls = null
	# 场上尸体统一清掉（组常量见 Groups.CORPSE）
	for corpse in get_tree().get_nodes_in_group(Groups.CORPSE):
		corpse.queue_free()
	# 选图/选种界面残留（若仍在树中）一并清理
	for child in dynamic.get_children():
		if child is SpeciesSelect or child is MapSelect:
			child.queue_free()
	species_select = null
	# 2) 重置运行期状态（day_t 保持不动：世界时间连续更自然）
	score_keeper.reset_all()
	is_over = false
	# 3) 从存档读回成长（死亡时已写盘：generation 已 +1）
	var d: Dictionary = SaveManager.load_save()
	var sid: String = d.get("species_id", DinoSpecies.ID_RAPTOR)
	var stage: int = d.get("growth_stage", 0)
	var gen: int = d.get("generation", 1)
	# 4) 复用现成生成函数重建运行期角色与 UI（顺序与 _start_game 一致）
	_spawn_hud()
	_spawn_player(sid, stage, gen)
	director.spawn_roster(stage)
	_spawn_touch_controls()
	hud.show_hint("第 %d 代开始：成长已保留，地形与植被延续，继续变强！" % gen)


## AI 死亡后续：生成尸体（按死亡物种上色），玩家击杀计数交给计分子系统
func _on_ai_died(ai: AIDino, by_player: bool) -> void:
	var corpse: AICorpse = CorpseScene.instantiate() as AICorpse
	corpse.species_id = ai.species.id
	corpse.species_colors = [ai.species.body_color, ai.species.dark_color]
	dynamic.add_child(corpse)
	corpse.global_position = ai.global_position
	if by_player:
		score_keeper.record_kill()


func _on_menu() -> void:
	skip_select = false
	get_tree().reload_current_scene()


# ================= 主循环 =================
func _process(delta: float) -> void:
	if is_over:
		return
	# 计分累计，每 0.5 秒刷新一次 HUD 分数
	if score_keeper.tick(delta):
		var gen: int = player.generation if player != null else 1
		# hud 在选图/选种界面期间尚未生成，需判空
		if hud != null:
			hud.set_score(int(score_keeper.survival_time), score_keeper.kill_count, gen)
	# 昼夜循环
	day_night.update(delta)
	# 生态维护：种群补员与传说霸主重生
	director.maintain_population(delta, player.growth_stage if player != null else 0)
	# 技能冷却显示（仅冲锋物种）
	if player != null and is_instance_valid(player) and player.has_charge_ability():
		touch_controls.set_ability_cooldown(player.charge_cooldown_timer, PlayerDino.CHARGE_COOLDOWN)
