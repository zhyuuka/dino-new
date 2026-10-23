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
const LoadingScreenScene: PackedScene = preload("res://scenes/LoadingScreen.tscn")

# 自然物分帧粒度：每 8 个自然物让出一帧（模型 load() 是同步的，必须在实例之间断点）
const LOADING_CHUNK: int = 8

# 真实资源预加载占整体进度的 0.0~0.70；之后的实例化阶段占 0.70~1.0
const PRELOAD_PROGRESS_END: float = 0.70
# 预加载超时（秒）：超时仅记录 warning 并继续进入世界生成，避免异常 IO 让玩家无限等待
const PRELOAD_TIMEOUT_SEC: float = 120.0

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
var loading_screen: LoadingScreen

# 预加载取回的模型资源强引用：防止刚取回就被资源缓存回收，
# 保证后续 NatureProp / Foliage / DinoVisual 的同步 load() 全部命中缓存
var _preload_refs: Array[Resource] = []

# 地形生成器（替代旧的 CSG 地板）
var terrain: TerrainGenerator
var _map_def: Maps.MapDef

# 运行期状态
var is_over: bool = false
# 世界是否已完整生成：false 期间（选图/选种/加载中）跳过补员、计分与技能显示，
# 避免地形未生成时把 AI 刷进虚空、以及访问尚未创建的 HUD/触屏节点
var _game_started: bool = false

# 开局选图/选种界面（选中后必须释放，避免残留叠在游戏画面上）
var map_select: MapSelect

# 光照与环境节点（仅用于注入 DayNightCycle / WorldBuilder）
var sun_light: DirectionalLight3D
var world_env: WorldEnvironment

# 子系统：昼夜 / 计分 / 世界构建 / AI 生态 / 随机事件
var day_night: DayNightCycle
var score_keeper: ScoreKeeper
var world_builder: WorldBuilder
var director: EcosystemDirector
var foliage_spawner: FoliageSpawner
var random_events: RandomEvents


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
	director.ai_egg_laid.connect(_on_ai_egg_laid)
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
	map_select = MapSelectScene.instantiate() as MapSelect
	dynamic.add_child(map_select)
	map_select.selected.connect(_on_map_selected)


func _on_map_selected(map_id: String) -> void:
	_map_def = Maps.by_id(map_id)
	day_night.set_map_def(_map_def)
	director.set_map_def(_map_def)
	# 选中后立即释放选图界面，否则它会一直叠在游戏画面上（曾导致 UI 层级残留）
	if map_select != null:
		map_select.queue_free()
		map_select = null
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
	director.set_map_def(_map_def)
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

	# ---- 全屏加载界面：先挂上并渲染一帧，再开始重活，避免点选后整屏"假死" ----
	# CanvasLayer.layer=100，盖住选种界面（默认 layer 1）；PROCESS_MODE_ALWAYS 由脚本设置
	loading_screen = LoadingScreenScene.instantiate() as LoadingScreen
	dynamic.add_child(loading_screen)
	_set_loading(0.0, "正在准备资源…")
	await get_tree().process_frame

	# 先真实预加载世界资产（模型在线程池解析，进度 0~70%）。此后 NatureProp / Foliage /
	# DinoVisual 里的同步 load() 全部命中资源缓存，主线程不再解析 gltf/glb
	await _preload_world_assets()

	# 世界资产（仅首局生成，死亡重开不重建）。地形 32k 三角面 + 三角网格碰撞，单帧构建
	_set_loading(0.70, "正在生成地形…")
	await get_tree().process_frame
	terrain = world_builder.spawn_terrain(dynamic, _map_def, world_env)
	director.set_terrain(terrain)
	_set_loading(0.78, "正在注入水源…")
	await get_tree().process_frame

	world_builder.spawn_water(dynamic, _map_def)
	_set_loading(0.82, "正在播撒植被…")
	await get_tree().process_frame

	foliage_spawner = world_builder.spawn_foliage(dynamic, _map_def, terrain)
	_set_loading(0.85, "正在种植自然物…")
	await get_tree().process_frame

	# 自然物仍分帧：每 8 个让出一帧，避免一次性挂载大量节点造成帧卡顿
	# （模型已预加载，_ready 内的同步 load() 只查缓存，不再读盘解析）
	await world_builder.spawn_nature(dynamic, _map_def, terrain, LOADING_CHUNK, _on_nature_progress)
	_set_loading(0.93, "正在布置资源点…")
	await get_tree().process_frame

	world_builder.spawn_resource_points(dynamic, terrain)
	_set_loading(0.95, "正在准备界面…")
	await get_tree().process_frame

	# 运行期角色与 UI（顺序：HUD → 玩家 → 生态 → 随机事件 → 触屏）
	_spawn_hud()
	_set_loading(0.96, "正在唤醒你的恐龙…")
	await get_tree().process_frame

	_spawn_player(species_id, stage, gen)
	_set_loading(0.98, "正在唤醒生态…")
	await get_tree().process_frame

	director.spawn_roster(stage)
	_spawn_random_events()
	_set_loading(1.0, "准备就绪")
	await get_tree().process_frame

	# 触屏与新手引导（依赖玩家已就绪，故放在最后）
	_spawn_touch_controls()
	# 世界与运行期节点全部就绪，开启 _process 中的补员/计分/技能通道
	_game_started = true
	hud.show_hint("管理好饥饿/口渴/体力。靠近湖泊按 E 或饮水键喝水，吃对的食物会成长。")
	hud.show_help()

	# 新手引导（自接线节点）：Main 侧只需挂一次，其余由节点自己完成——
	# 0.5s 周期扫描自动发现/重连玩家与 HUD（死亡重开重建后同样跟随）；
	# 引导已完成（Achievements 跨局存档标记）时其 _ready 内自毁，挂载零成本
	add_child(TutorialGuide.new())

	# 世界已完整可玩：淡出加载界面并释放
	await loading_screen.fade_out()
	loading_screen.queue_free()
	loading_screen = null


## 加载进度推进（ratio 为 0.0~1.0 小数；_restart_run 不显示加载界面，故此处判空）
func _set_loading(ratio: float, text: String) -> void:
	if loading_screen != null and is_instance_valid(loading_screen):
		loading_screen.set_progress(ratio, text)


## 自然物撒布的进度回调：0.85（起点）→ 0.92（完成），由 WorldBuilder 每帧块回调一次
func _on_nature_progress(done: int, total: int) -> void:
	var ratio: float = 0.85 + 0.07 * float(done) / float(maxi(total, 1))
	_set_loading(ratio, "正在种植自然物… %d/%d" % [done, total])


# ================= 资源预加载 =================
## 收集当前地图与世界会用到的全部模型路径（去重）：
## 自然物 res://assets/models/nature/<slug>/<slug>_1k.gltf + 全部恐龙 res://assets/models/<id>.glb。
## 恐龙 id 来自 DinoSpecies.all()，与物种数据库保持一致，避免在此硬编码文件名。
func _collect_world_asset_paths() -> Array[String]:
	var seen: Dictionary = {}
	var paths: Array[String] = []
	var slugs: Array = []
	if _map_def != null:
		slugs.append_array(_map_def.tree_models)
		slugs.append_array(_map_def.rock_models)
		slugs.append_array(_map_def.plant_models)
	for slug_value in slugs:
		var slug: String = str(slug_value)
		if slug.is_empty():
			continue
		var nature_path: String = "res://assets/models/nature/%s/%s_1k.gltf" % [slug, slug]
		if not seen.has(nature_path):
			seen[nature_path] = true
			paths.append(nature_path)
	for def in DinoSpecies.all():
		var sp: DinoSpecies.SpeciesDef = def as DinoSpecies.SpeciesDef
		if sp == null:
			continue
		var dino_path: String = "res://assets/models/%s.glb" % sp.id
		if not seen.has(dino_path):
			seen[dino_path] = true
			paths.append(dino_path)
	return paths


## 真实资源预加载（整体进度 0.0 → PRELOAD_PROGRESS_END）：全部模型交给 ResourceLoader 线程池
## 异步解析，每帧轮询各 path 的 status/progress 汇总出真实进度，主线程不再同步解析 gltf/glb。
## 全部完成后 load_threaded_get 取回并保存在 _preload_refs，后续同步 load() 直接命中缓存。
## 单项失败仅 warning 跳过；超过 PRELOAD_TIMEOUT_SEC 未完成则 warning 后继续，绝不无限等待。
func _preload_world_assets() -> void:
	var paths: Array[String] = _collect_world_asset_paths()
	if paths.is_empty():
		return
	_preload_refs.clear()
	var pending: Array[String] = []
	for p in paths:
		var err: Error = ResourceLoader.load_threaded_request(p, "PackedScene")
		# ERR_BUSY：同路径已有请求在途，继续轮询即可；其他错误记录后跳过，不阻塞进局
		if err == OK or err == ERR_BUSY:
			pending.append(p)
		else:
			push_warning("资源预加载跳过 %s：load_threaded_request 返回错误 %d" % [p, err])
	var total: int = maxi(pending.size(), 1)
	var finished: int = 0
	var ratio: float = 0.0
	var deadline_msec: int = Time.get_ticks_msec() + int(PRELOAD_TIMEOUT_SEC * 1000.0)
	_set_loading(0.0, "正在加载资源…")
	while not pending.is_empty():
		if Time.get_ticks_msec() >= deadline_msec:
			push_warning("资源预加载超时 %.0f 秒，跳过剩余 %d 项（进入世界后按需同步加载）" % [PRELOAD_TIMEOUT_SEC, pending.size()])
			break
		var partial: float = 0.0
		var completed_idx: Array[int] = []
		var failed_idx: Array[int] = []
		for i in pending.size():
			var path: String = pending[i]
			var progress: Array = []
			var status: int = ResourceLoader.load_threaded_get_status(path, progress)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				completed_idx.append(i)
			elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				if not progress.is_empty():
					partial += clampf(float(progress[0]), 0.0, 1.0)
			else:
				# FAILED / INVALID_RESOURCE：记录并跳过该路径，不阻塞整体流程
				push_warning("资源预加载失败 %s（status=%d），已跳过" % [path, status])
				failed_idx.append(i)
		# 已完成项取回资源并保持强引用，防止刚加载就被缓存回收
		for i in range(completed_idx.size() - 1, -1, -1):
			var idx: int = completed_idx[i]
			var res: Resource = ResourceLoader.load_threaded_get(pending[idx])
			if res != null:
				_preload_refs.append(res)
			else:
				push_warning("资源预加载取回为空 %s" % pending[idx])
			pending.remove_at(idx)
		for i in range(failed_idx.size() - 1, -1, -1):
			pending.remove_at(failed_idx[i])
		finished += completed_idx.size() + failed_idx.size()
		# 真实进度 = （已完成 + 失败跳过 + 在途项各自 progress） / 总数
		ratio = clampf((float(finished) + partial) / float(total), 0.0, 1.0)
		_set_loading(PRELOAD_PROGRESS_END * ratio, "正在加载资源… %d/%d" % [finished, total])
		if pending.is_empty():
			break
		await get_tree().process_frame
	# 正常完成或超时都推进到本阶段终点，无缝衔接后续实例化阶段
	_set_loading(PRELOAD_PROGRESS_END, "正在加载资源… %d/%d" % [finished, total])


# ================= 玩家 / HUD / 触屏 =================
func _spawn_player(species_id: String, stage: int, gen: int, at: Vector3 = PLAYER_SPAWN) -> void:
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
	player.egg_laid.connect(_on_player_egg_laid)
	dynamic.add_child(player)
	var py: float = terrain.get_height(at.x, at.z) if terrain != null else at.y
	player.global_position = Vector3(at.x, py + 0.2, at.z)


func _spawn_hud() -> void:
	hud = HUDScene.instantiate() as HUD
	dynamic.add_child(hud)
	hud.menu_pressed.connect(_on_menu)


## 创建随机事件子系统并注入依赖、接线横幅信号（开局 / 死亡重开各调用一次）
func _spawn_random_events() -> void:
	random_events = RandomEvents.new()
	random_events.director = director
	random_events.day_night = day_night
	random_events.foliage_spawner = foliage_spawner
	random_events.event_started.connect(_on_event_started)
	random_events.event_ended.connect(_on_event_ended)
	add_child(random_events)


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


# ================= 蛋 / 代际 =================
## AI 产蛋：挂到动态容器并接孵化回调。bind 把蛋引用追加在信号参数之后，
## 便于孵化成败回传：成功销毁蛋壳，满员让蛋自行延时重试（蛋只管计时与信号）
func _on_ai_egg_laid(egg: DinoEgg) -> void:
	dynamic.add_child(egg)
	egg.hatched.connect(_on_egg_hatched.bind(egg))


## AI 蛋孵化请求：生态未满 → 落地幼体并销毁蛋；满员 → 通知蛋延时 20s 重试
func _on_egg_hatched(species_id: String, pos: Vector3, egg: DinoEgg) -> void:
	if director.hatch_ai(species_id, pos):
		egg.queue_free()
	else:
		egg.notify_hatch_failed()


## 玩家产蛋：写入当前代际并挂到动态容器。蛋是“跨代”资产：_restart_run 的释放清单不动蛋，
## 玩家死亡后从自己的蛋重生（见 _restart_run 第 3.5 步）
func _on_player_egg_laid(egg: DinoEgg) -> void:
	# 玩家产蛋方（PlayerDino）不感知代际编号之外的编排信息，由 Main 补写代际标记：
	# _find_player_egg 以 from_generation 最大者作为最新重生锚点
	egg.from_generation = player.generation if player != null and is_instance_valid(player) else 1
	# 玩家蛋上限 3：极端情况下（一局内连续产蛋 / 多代未消费）先销毁最旧的一枚再挂新的，
	# 避免玩家蛋无限堆积（同代际并列时取扫描到的第一枚）
	var player_eggs: Array[DinoEgg] = []
	for n in get_tree().get_nodes_in_group(Groups.EGG):
		var e := n as DinoEgg
		if e != null and e.owner_player:
			player_eggs.append(e)
	if player_eggs.size() >= 3:
		var oldest: DinoEgg = player_eggs[0]
		for e in player_eggs:
			if e.from_generation < oldest.from_generation:
				oldest = e
		oldest.queue_free()
	dynamic.add_child(egg)


## 找最新的一枚玩家自己的蛋（跨代重生锚点）：按 from_generation 取最大者
func _find_player_egg() -> DinoEgg:
	var best: DinoEgg = null
	for n in get_tree().get_nodes_in_group(Groups.EGG):
		var e := n as DinoEgg
		if e != null and e.owner_player:
			if best == null or e.from_generation > best.from_generation:
				best = e
	return best


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
	# 成就：进化里程碑（unlock 幂等；开局带存档阶段触发同样成立）
	if stage >= 2:
		Achievements.unlock("evolution_2")
	if stage >= DinoSpecies.MAX_STAGE:
		Achievements.unlock("evolution_max")

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


## 随机事件横幅转发 + 见证类成就。RandomEvents 的 event_started/ended 信号只携带文案、
## 未暴露 kind，故按各事件 start/end 处理函数返回文案的前缀判定类型
## （"一群"=兽群迁徙开场，"风暴平息"=风暴收场，见 RandomEvents._event_catalog）。
func _on_event_started(text: String) -> void:
	hud.show_banner(text)
	if text.begins_with("一群"):
		Achievements.unlock("herd_witness")   # 兽群迁徙开场 = 见证兽群


func _on_event_ended(text: String) -> void:
	hud.show_banner(text)
	if text.begins_with("风暴平息"):
		Achievements.unlock("storm_survivor") # 风暴收场 = 活过风暴


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
## 保留世界资产（地形、水源、植被、资源点、树石、环境音）与蛋（Groups.EGG，跨代资产）；
## 有玩家蛋则从蛋中重生（代际），无则按存档续代
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
	# 随机事件旧实例释放（_exit_tree 会回滚未结束的风暴/丰饶期效果）
	if random_events != null:
		random_events.queue_free()
		random_events = null
	# 场上尸体统一清掉（组常量见 Groups.CORPSE）
	for corpse in get_tree().get_nodes_in_group(Groups.CORPSE):
		corpse.queue_free()
	# 选图/选种界面残留（若仍在树中）一并清理
	for child in dynamic.get_children():
		if child is SpeciesSelect or child is MapSelect:
			child.queue_free()
	species_select = null
	map_select = null
	# 2) 重置运行期状态（day_t 保持不动：世界时间连续更自然）
	score_keeper.reset_all()
	is_over = false
	# 世界资产自开局起已完整，重开后保持 _process 的补员/计分/技能通道开启
	_game_started = true
	# 3) 从存档读回成长（死亡时已写盘：generation 已 +1）
	var d: Dictionary = SaveManager.load_save()
	var sid: String = d.get("species_id", DinoSpecies.ID_RAPTOR)
	var stage: int = d.get("growth_stage", 0)
	var gen: int = d.get("generation", 1)
	# 3.5) 跨代重生：上一代留下的玩家蛋还在 → 从蛋的位置出生，
	#      成长取“蛋快照与存档较大者”（蛋快照早于死亡存档时以存档为准）
	var egg := _find_player_egg()
	var spawn_pos: Vector3 = PLAYER_SPAWN
	if egg != null:
		spawn_pos = egg.global_position
		stage = maxi(stage, egg.growth_stage_snapshot)
	# 只消费最新一枚作为重生锚点：登记完出生点后，连同其余旧蛋一并销毁，
	# 避免多代累积的旧蛋永久占位并计入蛋总数
	for n in get_tree().get_nodes_in_group(Groups.EGG):
		var e := n as DinoEgg
		if e != null and e.owner_player:
			e.queue_free()
	# 4) 复用现成生成函数重建运行期角色与 UI（顺序与 _start_game 一致）
	_spawn_hud()
	_spawn_player(sid, stage, gen, spawn_pos)
	if egg != null:
		hud.show_banner("从蛋中诞生！第 %d 代" % gen)
	director.spawn_roster(stage)
	_spawn_random_events()
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
		# 成就：首杀与十杀（kill_count 只在此处变化，就地判定；unlock 幂等，无需判重）
		Achievements.unlock("first_kill")
		if score_keeper.kill_count >= 10:
			Achievements.unlock("kills_10")


func _on_menu() -> void:
	skip_select = false
	get_tree().reload_current_scene()


# ================= 主循环 =================
func _process(delta: float) -> void:
	if is_over:
		return
	# 选图/选种/加载期间世界尚未就绪：补员会把 AI 刷在未生成的地形上（y=1.5）掉入虚空，
	# 计分与技能显示也依赖玩家/HUD/触屏节点，故统一由 _game_started 门禁跳过。
	if _game_started:
		# 计分累计，每 0.5 秒刷新一次 HUD 分数
		if score_keeper.tick(delta):
			var gen: int = player.generation if player != null else 1
			# hud 在选图/选种界面期间尚未生成，需判空
			if hud != null:
				hud.set_score(int(score_keeper.survival_time), score_keeper.kill_count, gen)
			# 成就：存活满 5 分钟（随计分 tick 判定；unlock 幂等）
			if score_keeper.survival_time >= 300.0:
				Achievements.unlock("survival_300")
		# 生态维护：种群补员与传说霸主重生
		director.maintain_population(delta, player.growth_stage if player != null else 0)
		# 技能冷却显示（仅冲锋物种）；touch_controls 在加载分帧期间尚未创建，需判空
		if player != null and is_instance_valid(player) and player.has_charge_ability():
			if touch_controls != null and is_instance_valid(touch_controls):
				touch_controls.set_ability_cooldown(player.charge_cooldown_timer, PlayerDino.CHARGE_COOLDOWN)
	# 昼夜循环：菜单背景也保留昼夜变化，始终推进
	day_night.update(delta)
