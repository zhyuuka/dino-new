extends SceneTree
## 用法：godot --headless -s res://tests/run_tests.gd
## 纯数据层单测：不依赖任何 autoload、不加载任何美术资源。
## 注意（Godot 4.4 已查证 main.cpp）：-s 且主循环为 SceneTree 的 game 运行仍会加载 autoload，
## 故 GameState/AudioManager 的 _ready 会照常执行一次，但被测类均为 class_name 静态类，不受影响。
## 依赖编辑器 import 生成的全局类缓存（CI 中先跑 import 步骤）。
## 全部通过则 quit(0)，任一失败打印 "FAIL: ..." 并 quit(1)。

## 断言计数
var _passed: int = 0
var _failed: int = 0


func _initialize() -> void:
	_test_groups()
	_test_physics_layers()
	_test_maps()
	_test_dino_species()
	_test_save_manager()
	_test_save_repository()
	_test_vitals()
	_test_combat_rules()
	_test_growth_rules()
	print("PASSED: %d / FAILED: %d" % [_passed, _failed])
	quit(0 if _failed == 0 else 1)


## 小断言助手：通过计数，失败打印 FAIL 行并计数
func check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: " + name)


# --- Groups：全局组名常量 ----------------------------------------------------

func _test_groups() -> void:
	check(Groups.PLAYER == "player", "Groups.PLAYER 应为 player")
	check(Groups.AI == "ai", "Groups.AI 应为 ai")
	check(Groups.CORPSE == "corpse", "Groups.CORPSE 应为 corpse")
	check(Groups.PLANT == "plant", "Groups.PLANT 应为 plant")
	check(Groups.WATER == "water", "Groups.WATER 应为 water")
	check(Groups.RESOURCE == "resource", "Groups.RESOURCE 应为 resource")
	check(Groups.EGG == "egg", "Groups.EGG 应为 egg")
	check(Groups.HUD == "hud", "Groups.HUD 应为 hud")


# --- PhysicsLayers：物理层常量化 ---------------------------------------------

func _test_physics_layers() -> void:
	var layers: Array[int] = [
		PhysicsLayers.WORLD, PhysicsLayers.PLAYER_BODY, PhysicsLayers.AI_BODY,
		PhysicsLayers.PROP_BODY, PhysicsLayers.INTERACT, PhysicsLayers.TRIGGER,
	]
	var no_overlap: bool = true
	for i in layers.size():
		for j in range(i + 1, layers.size()):
			if (layers[i] & layers[j]) != 0:
				no_overlap = false
	check(no_overlap, "PhysicsLayers 各层位应两两不重叠")
	check(
			(PhysicsLayers.PLAYER_MASK & PhysicsLayers.WORLD) != 0
			and (PhysicsLayers.PLAYER_MASK & PhysicsLayers.AI_BODY) != 0
			and (PhysicsLayers.PLAYER_MASK & PhysicsLayers.PROP_BODY) != 0,
			"PLAYER_MASK 应包含 WORLD/AI_BODY/PROP_BODY")
	check(PhysicsLayers.FOLIAGE_AREA_MASK == 6,
			"FOLIAGE_AREA_MASK 应为 6（PLAYER_BODY|AI_BODY）")


# --- Maps：地图预设库 --------------------------------------------------------

func _test_maps() -> void:
	var all_maps: Array = Maps.all()
	check(all_maps.size() == 4, "Maps.all() 应返回 4 张地图")
	var default_map: Maps.MapDef = Maps.by_id(Maps.DEFAULT_MAP_ID)
	check(default_map.id == Maps.DEFAULT_MAP_ID, "by_id(DEFAULT_MAP_ID) 应命中默认地图")
	var fallback: Maps.MapDef = Maps.by_id("不存在的id")
	check(fallback == all_maps[0], "by_id(不存在的id) 应回退到第一张地图")
	for d in all_maps:
		check("water_points" in d and d.water_points is Array,
				"MapDef[%s].water_points 字段应存在且为数组" % d.id)
		check("plant_count" in d and d.plant_count is int and d.plant_count > 0,
				"MapDef[%s].plant_count 字段应存在且为正整数" % d.id)


# --- DinoSpecies：物种数据库 -------------------------------------------------

func _test_dino_species() -> void:
	var ids: Array = [
		DinoSpecies.ID_RAPTOR, DinoSpecies.ID_TRIKE, DinoSpecies.ID_TREX,
		DinoSpecies.ID_ANKY, DinoSpecies.ID_CARNO, DinoSpecies.ID_GALLI,
	]
	for id in ids:
		check(DinoSpecies.by_id(id) != null, "DinoSpecies.by_id(%s) 应非 null" % id)
	check(DinoSpecies.by_id("nope") == null, "by_id(未知id) 应返回 null")
	# stage_info 越界输入应被钳制到 [0, MAX_STAGE]，不越界访问 GROWTH_STAGES
	check(DinoSpecies.stage_info(-1) is Dictionary and DinoSpecies.stage_info(-1) == DinoSpecies.stage_info(0),
			"stage_info(-1) 应回退到幼体(下标 0)")
	check(DinoSpecies.stage_info(99) is Dictionary and DinoSpecies.stage_info(99) == DinoSpecies.stage_info(DinoSpecies.MAX_STAGE),
			"stage_info(99) 应回退到霸主(下标 MAX_STAGE)")


# --- SaveManager：兼容门面 + SaveRepository：唯一存档 IO -----------------------

## 直接覆写原始文件（模拟损坏档 / 未来版本档 / 外部旧档）
func _write_raw(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		check(false, "测试准备失败：无法写入 " + path)
		return
	f.store_string(content)
	f.close()


## 读取原始文件文本（断言备份内容用）
func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var txt: String = f.get_as_text()
	f.close()
	return txt


## 读取并解析 JSON 字典；失败返回空字典（测试侧不复用生产代码）
func _read_dict(path: String) -> Dictionary:
	var txt: String = _read_text(path)
	if txt.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = parsed
	return d


## 删除 user:// 下指定文件（保证测试确定性）
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


## 清空存档全家桶：主档 / tmp / 上一份 / 未来版本 / 损坏隔离
func _clean_save_files() -> void:
	var paths: Array[String] = [
		SaveRepository.SAVE_PATH,
		SaveRepository.SAVE_PATH + ".tmp",
		SaveRepository.BAK_PATH,
		SaveRepository.FUTURE_BAK_PATH,
		SaveRepository.CORRUPT_BAK_PATH,
	]
	for path in paths:
		_remove_file(path)


func _test_save_manager() -> void:
	# 清场：删除可能残留的存档与备份，保证从“无档”状态开始
	_clean_save_files()

	# 1) 无档状态
	check(not SaveManager.has_save(), "无档时 has_save() 应为 false")
	check(not SaveManager.has_progress(), "无档时 has_progress() 应为 false")
	var empty: Dictionary = SaveManager.load_save()
	check(empty.get("map_id", "") == Maps.DEFAULT_MAP_ID, "无档时 load_save() 应回退默认 map_id")

	# 2) roundtrip：门面写入后读回全字段一致
	var payload := {
		"species_id": "raptor",
		"growth_stage": 2,
		"generation": 3,
		"map_id": "canyon",
		"best_time": 99,
		"best_kills": 5,
	}
	SaveManager.write_save(payload.duplicate())
	check(SaveManager.has_save(), "写入后 has_save() 应为 true")
	var loaded: Dictionary = SaveManager.load_save()
	var raw: Dictionary = _read_dict(SaveManager.SAVE_PATH)
	check(int(raw.get(SaveRepository.KEY_SAVE_VERSION, -1)) == SaveManager.SAVE_VERSION,
			"save_version 应为 2")
	for field in ["species_id", "growth_stage", "generation", "map_id", "best_time", "best_kills"]:
		check(loaded.get(field) == payload[field], "roundtrip 字段 %s 应一致" % field)
	check(not FileAccess.file_exists(SaveManager.SAVE_PATH + ".tmp"), "write_save 后不应残留 tmp 文件")
	check(SaveManager.has_progress(), "完整存档时 has_progress() 应为 true")

	# 3) 缺物种信息的档（直接落盘，模拟外部/旧版写入）：has_save 为 true 但 has_progress 为 false
	_write_raw(SaveManager.SAVE_PATH, JSON.stringify({
		SaveRepository.KEY_SAVE_VERSION: SaveRepository.SAVE_VERSION,
		"map_id": "snow",
	}))
	check(SaveManager.has_save(), "写入部分档后 has_save() 应为 true")
	check(not SaveManager.has_progress(), "缺 species_id 时 has_progress() 应为 false")

	# 4) 损坏档：非法 JSON → 回退默认；现场隔离为 save.corrupt.bak
	_write_raw(SaveManager.SAVE_PATH, "not json{{")
	check(SaveManager.has_save(), "损坏档文件存在时 has_save() 应为 true")
	var corrupt: Dictionary = SaveManager.load_save()
	check(corrupt.get("map_id", "") == Maps.DEFAULT_MAP_ID, "损坏档 load_save() 应回退默认 map_id")
	check(corrupt.get("species_id", "") == DinoSpecies.ID_RAPTOR, "损坏档应回退默认物种 raptor")
	check(not SaveManager.has_progress(), "损坏档 has_progress() 应为 false")

	# 5) 未来版本档：save_version 高于当前 → 回退默认，原文件保留
	_write_raw(SaveManager.SAVE_PATH, JSON.stringify({"save_version": 99, "species_id": "trex"}))
	var future: Dictionary = SaveManager.load_save()
	check(future.get("species_id", "") == DinoSpecies.ID_RAPTOR, "未来版本档应回退默认物种 raptor")
	check(future.get("map_id", "") == Maps.DEFAULT_MAP_ID, "未来版本档回退后 map_id 应为默认值")


## Repository 层：迁移链 / 备份 / 原子写 / 未来版本 / 损坏隔离（≥12 条断言）
func _test_save_repository() -> void:
	# 0) 清场：save.json / save.bak / save.future.bak / save.corrupt.bak / *.tmp
	_clean_save_files()

	# 1) 无档 → 默认档，且读取不产生文件
	var d0: PlayerProfile = SaveRepository.load_profile()
	check(not SaveRepository.has_save(), "Repository: 无档时 has_save 应为 false")
	check(d0.species_id == DinoSpecies.ID_RAPTOR and d0.growth_stage == 0 and d0.generation == 1,
			"Repository: 无档应返回默认物种/成长/代际")
	check(d0.map_id == Maps.DEFAULT_MAP_ID and d0.best_time == 0 and d0.best_kills == 0,
			"Repository: 默认档地图与最佳成绩应为默认值")
	check(not FileAccess.file_exists(SaveRepository.SAVE_PATH),
			"Repository: 无档读取不应创建存档文件")

	# 2) 往返：save_profile → load_profile 全字段一致
	var p1 := PlayerProfile.defaults()
	p1.species_id = DinoSpecies.ID_TREX
	p1.growth_stage = 3
	p1.generation = 4
	p1.map_id = "canyon"
	p1.best_time = 99
	p1.best_kills = 5
	check(SaveRepository.save_profile(p1), "Repository: save_profile 应返回 true")
	var p1b: PlayerProfile = SaveRepository.load_profile()
	check(p1b.species_id == p1.species_id and p1b.growth_stage == p1.growth_stage,
			"Repository: 往返后物种/成长阶段应一致")
	check(p1b.generation == p1.generation and p1b.map_id == p1.map_id,
			"Repository: 往返后代际/地图应一致")
	check(p1b.best_time == p1.best_time and p1b.best_kills == p1.best_kills,
			"Repository: 往返后最佳成绩应一致")
	check(not FileAccess.file_exists(SaveRepository.SAVE_PATH + ".tmp"),
			"Repository: 原子写后不应残留 tmp")
	var raw1: Dictionary = _read_dict(SaveRepository.SAVE_PATH)
	check(int(raw1.get(SaveRepository.KEY_SAVE_VERSION, -1)) == SaveRepository.SAVE_VERSION,
			"Repository: 写盘应带 save_version=2")
	check(int(raw1.get(SaveRepository.KEY_PROFILE_VERSION, -1)) == SaveRepository.SAVE_VERSION,
			"Repository: 写盘应带 profile_version=2")

	# 3) 备份轮换：第二次写入后 save.bak 为上一次内容
	var p2: PlayerProfile = SaveRepository.load_profile()
	p2.best_time = 120
	check(SaveRepository.save_profile(p2), "Repository: 第二次写入应成功")
	check(FileAccess.file_exists(SaveRepository.BAK_PATH),
			"Repository: 第二次写入后应生成 save.bak")
	var bak: Dictionary = _read_dict(SaveRepository.BAK_PATH)
	check(int(bak.get(PlayerProfile.KEY_BEST_TIME, -1)) == 99,
			"Repository: save.bak 应为上一次内容（best_time=99）")

	# 4) v1 旧档（无 save_version）：字段保留 + 迁移后 save_version/profile_version 变 2
	_clean_save_files()
	_write_raw(SaveRepository.SAVE_PATH, JSON.stringify({
		"species_id": "trex", "growth_stage": 2, "generation": 3,
		"map_id": "canyon", "best_time": 42, "best_kills": 7, "legacy_note": "v1",
	}))
	var m1: PlayerProfile = SaveRepository.load_profile()
	check(m1.species_id == "trex" and m1.growth_stage == 2 and m1.generation == 3,
			"Repository: v1 旧档应保留物种/成长/代际")
	check(m1.map_id == "canyon" and m1.best_time == 42 and m1.best_kills == 7,
			"Repository: v1 旧档应保留地图/最佳成绩")
	var raw_m1: Dictionary = _read_dict(SaveRepository.SAVE_PATH)
	check(int(raw_m1.get(SaveRepository.KEY_SAVE_VERSION, -1)) == 2,
			"Repository: v1 迁移后 save_version 应变为 2")
	check(int(raw_m1.get(SaveRepository.KEY_PROFILE_VERSION, -1)) == 2,
			"Repository: v1 迁移后应补 profile_version=2")
	check(str(raw_m1.get("legacy_note", "")) == "v1",
			"Repository: v1 迁移应保留未知字段（不静默丢档）")

	# 5) 显式 v1（save_version=1）：缺字段补默认，迁移后以 v2 落盘
	_clean_save_files()
	_write_raw(SaveRepository.SAVE_PATH, JSON.stringify({
		"save_version": 1, "species_id": "anky", "growth_stage": 1, "generation": 2,
	}))
	var m2: PlayerProfile = SaveRepository.load_profile()
	check(m2.species_id == "anky" and m2.growth_stage == 1 and m2.generation == 2,
			"Repository: 显式 v1 档字段应保留")
	check(m2.map_id == Maps.DEFAULT_MAP_ID and m2.best_time == 0 and m2.best_kills == 0,
			"Repository: 显式 v1 缺字段应补默认值")
	check(int(_read_dict(SaveRepository.SAVE_PATH).get(SaveRepository.KEY_SAVE_VERSION, -1)) == 2,
			"Repository: 显式 v1 档迁移后应以 v2 落盘")

	# 6) 未来版本：返回默认档 + save.future.bak，原文件保留
	_clean_save_files()
	_write_raw(SaveRepository.SAVE_PATH, JSON.stringify({
		"save_version": 99, "profile_version": 99, "species_id": "trex",
		"growth_stage": 4, "generation": 9, "map_id": "snow",
		"best_time": 1234, "best_kills": 88,
	}))
	var f1: PlayerProfile = SaveRepository.load_profile()
	check(f1.species_id == DinoSpecies.ID_RAPTOR and f1.growth_stage == 0 and f1.generation == 1
			and f1.map_id == Maps.DEFAULT_MAP_ID and f1.best_time == 0 and f1.best_kills == 0,
			"Repository: 未来版本应返回默认档")
	check(FileAccess.file_exists(SaveRepository.FUTURE_BAK_PATH),
			"Repository: 未来版本应生成 save.future.bak")
	check(FileAccess.file_exists(SaveRepository.SAVE_PATH),
			"Repository: 未来版本原文件应保留不删")
	check(str(_read_dict(SaveRepository.FUTURE_BAK_PATH).get(PlayerProfile.KEY_SPECIES, "")) == "trex",
			"Repository: save.future.bak 内容应为原档")

	# 7) 损坏档：返回默认档 + save.corrupt.bak 保留现场
	_clean_save_files()
	_write_raw(SaveRepository.SAVE_PATH, "not json{{")
	var c1: PlayerProfile = SaveRepository.load_profile()
	check(c1.species_id == DinoSpecies.ID_RAPTOR and c1.growth_stage == 0 and c1.generation == 1,
			"Repository: 损坏档应返回默认档")
	check(FileAccess.file_exists(SaveRepository.CORRUPT_BAK_PATH),
			"Repository: 损坏档应生成 save.corrupt.bak")
	check(_read_text(SaveRepository.CORRUPT_BAK_PATH) == "not json{{",
			"Repository: save.corrupt.bak 应保留损坏现场")

	# 8) 坏档写入不得顶掉已有的好备份
	_clean_save_files()
	var g1 := PlayerProfile.defaults()
	g1.best_time = 11
	SaveRepository.save_profile(g1)
	var g2 := PlayerProfile.defaults()
	g2.best_time = 22
	SaveRepository.save_profile(g2)
	_write_raw(SaveRepository.SAVE_PATH, "broken{{")
	check(SaveRepository.save_profile(PlayerProfile.defaults()),
			"Repository: 坏档存在时仍应能写入新档")
	check(int(_read_dict(SaveRepository.BAK_PATH).get(PlayerProfile.KEY_BEST_TIME, -1)) == 11,
			"Repository: 坏档写入不应覆盖上一份好备份")


# --- Vitals：生存数值纯逻辑层 -------------------------------------------------

## 与 PlayerDino 常量完全一致的注入速率（测试侧自带，避免依赖 Node 常量）
func _player_rates() -> Dictionary:
	return {
		"hunger_interval": 14.0,
		"thirst_interval": 12.0,
		"thirst_sprint_mult": 0.5,
		"stamina_drain": 22.0,
		"stamina_regen": 14.0,
		"stamina_lock": 18.0,
		"drag_stamina_mult": 1.5,
		"drink_rate": 45.0,
		"starve_interval": 5.0,
		"starve_damage": 6,
		"thirst_starve_interval": 4.0,
		"thirst_starve_damage": 5,
		"eat_meat_hunger": 28,
		"eat_plant_hunger": 10,
		"eat_plant_thirst": 4,
		"eat_egg_hunger": 10,
		"survival_step_once": false,
	}


func _new_player_vitals() -> Vitals:
	var v := Vitals.new()
	v.setup(100, 100, 100, _player_rates())
	return v


## 模拟 60fps 逐帧结算
func _tick_frames(v: Vitals, frames: int, sprinting: bool = false, dragging: bool = false) -> void:
	for i in frames:
		v.tick(1.0 / 60.0, sprinting, dragging)


func _test_vitals() -> void:
	# 初始满值
	var v := _new_player_vitals()
	var s: Dictionary = v.get_state()
	check(s["hunger"] == 100 and s["thirst"] == 100 and s["stamina"] == 100,
			"Vitals.setup 后三项应满值")
	check(s["max_hunger"] == 100 and s["max_thirst"] == 100 and s["max_stamina"] == 100,
			"Vitals.get_state 应带出上限")

	# 45 秒不冲刺：饥饿 45/14=3.214→3，口渴 45/12=3.75→3
	v = _new_player_vitals()
	v.tick(45.0, false, false)
	check(v.hunger == 97, "45s 不冲刺饥饿应 100-3=97，实际 %d" % v.hunger)
	check(v.thirst == 97, "45s 不冲刺口渴应 100-3=97，实际 %d" % v.thirst)

	# has_changed：单帧无整数变化为 false，跨过 1 点后为 true
	v = _new_player_vitals()
	v.tick(1.0 / 60.0, false, false)
	check(not v.has_changed(), "单帧未跨整数时 has_changed 应为 false")
	v.tick(14.0, false, false)
	check(v.has_changed(), "跨过 1 点饥饿后 has_changed 应为 true")

	# 冲刺体力：1 秒 -22
	v = _new_player_vitals()
	v.tick(1.0, true, false)
	check(v.stamina == 78, "冲刺 1s 体力应 100-22=78，实际 %d" % v.stamina)
	# 叼尸体力：1 秒 -22×1.5=-33
	v = _new_player_vitals()
	v.tick(1.0, false, true)
	check(v.stamina == 67, "叼尸移动 1s 体力应 100-33=67，实际 %d" % v.stamina)
	# 不冲刺回复：14/s
	v.tick(1.0, false, false)
	check(v.stamina == 81, "不冲刺 1s 体力应 67+14=81，实际 %d" % v.stamina)

	# 力竭锁：体力归零后不能冲刺；回满到 18 才解除
	v = _new_player_vitals()
	v.tick(10.0, true, false)
	check(v.stamina == 0, "长时间冲刺体力应归零")
	check(not v.can_sprint(), "体力归零后 can_sprint 应为 false")
	v.restore_stamina(17)
	v.tick_stamina(0.0, false, false)
	check(not v.can_sprint(), "回体力到 17（<18）仍应力竭锁定")
	v.restore_stamina(1)
	v.tick_stamina(0.0, false, false)
	check(v.can_sprint(), "回体力到 18 应解除力竭锁")

	# 冲刺口渴：间隔 12×0.5=6s，6 秒掉 1 点；不冲刺 6 秒不掉
	v = _new_player_vitals()
	v.tick(6.0, true, false)
	check(v.thirst == 99, "冲刺 6s 口渴应 -1，实际 %d" % v.thirst)
	v = _new_player_vitals()
	v.tick(6.0, false, false)
	check(v.thirst == 100, "不冲刺 6s 口渴不应下降，实际 %d" % v.thirst)

	# 饮水回复：先扣到 50，再按 45/s 回复
	v = _new_player_vitals()
	v.tick(600.0, false, false)
	check(v.thirst == 50, "600s 不冲刺口渴应 100-50=50，实际 %d" % v.thirst)
	v.drink(1.0)
	check(v.thirst == 95, "饮水 1s 应回复 45，实际 %d" % v.thirst)
	v.drink(1.0)
	check(v.thirst == 100, "饮水应被上限 100 夹取，实际 %d" % v.thirst)

	# 进食：肉 +28 饥饿；植物 +10 饥饿 / +4 口渴
	v = _new_player_vitals()
	v.consume_hunger(50)
	v.eat("meat")
	check(v.hunger == 78, "吃肉应 +28 饥饿，实际 %d" % v.hunger)
	v = _new_player_vitals()
	v.tick(600.0, false, false)   # 口渴 50、饥饿 58
	v.eat("plant")
	check(v.hunger == 68, "吃植物应 +10 饥饿，实际 %d" % v.hunger)
	check(v.thirst == 54, "吃植物应 +4 口渴，实际 %d" % v.thirst)
	v.eat("egg")
	check(v.hunger == 78, "偷蛋应 +10 饥饿，实际 %d" % v.hunger)

	# 长时间 60fps 逐帧结算：余数不丢（3600 帧 ≈ 60s；饥饿 60/14≈4.28→4，口渴 60/12=5）
	v = _new_player_vitals()
	_tick_frames(v, 3600)
	check(v.hunger == 96, "3600 帧后饥饿应 100-4=96，实际 %d" % v.hunger)
	check(v.thirst >= 95 and v.thirst <= 96,
			"3600 帧后口渴应在 95~96（浮点末尾残差与旧实现一致），实际 %d" % v.thirst)

	# 饿死伤害：饥饿归零后每 5s 掉 6，拉取后清零
	v = _new_player_vitals()
	v.consume_hunger(100)
	v.tick(5.0, false, false)
	check(v.pull_starve_damage() == 6, "饥饿为 0 满 5s 应产生 6 点饿死伤害")
	check(v.pull_starve_damage() == 0, "饿死伤害拉取后应清零")
	v.tick(4.9, false, false)
	check(v.pull_starve_damage() == 0, "不足 5s 不应再次产生饿死伤害")
	v.tick(0.1, false, false)
	check(v.pull_starve_damage() == 6, "累计满 5s 应再次产生 6 点饿死伤害")

	# 渴死伤害：max_thirst=0 直接构造口渴归零，4s 掉 5
	v = Vitals.new()
	v.setup(100, 0, 0, _player_rates())
	v.tick(4.0, false, false)
	check(v.pull_thirst_damage() == 5, "口渴为 0 满 4s 应产生 5 点渴死伤害")
	check(v.pull_thirst_damage() == 0, "渴死伤害拉取后应清零")

	# AI 速率注入：饥饿 50s/点、口渴 45s/点
	var ai_rates: Dictionary = _player_rates()
	ai_rates["hunger_interval"] = 50.0
	ai_rates["thirst_interval"] = 45.0
	ai_rates["thirst_starve_interval"] = 0.0
	ai_rates["survival_step_once"] = true
	var ai_v := Vitals.new()
	ai_v.setup(100, 100, 0, ai_rates)
	ai_v.tick(45.0, false, false)
	check(ai_v.hunger == 100, "AI 45s 未到 50s 饥饿不应下降")
	check(ai_v.thirst == 99, "AI 45s 口渴应 -1，实际 %d" % ai_v.thirst)
	check(ai_v.stamina == 0 and not ai_v.can_sprint(), "AI 无体力，不应可冲刺")
	# AI 秒表模式：单帧 delta=100s 也只各掉 1 点（与旧 AIDino 每帧最多 1 点一致）
	ai_v = Vitals.new()
	ai_v.setup(100, 100, 0, ai_rates)
	ai_v.tick(100.0, false, false)
	check(ai_v.hunger == 99, "AI 单帧 100s 饥饿应只 -1，实际 %d" % ai_v.hunger)
	check(ai_v.thirst == 99, "AI 单帧 100s 口渴应只 -1，实际 %d" % ai_v.thirst)


# --- CombatRules：战斗数值纯规则 ---------------------------------------------

func _test_combat_rules() -> void:
	# 猎食：草食恒定可猎；肉食需严格 < 攻击者 ×0.9；非肉食攻击者不猎
	check(CombatRules.can_hunt(1.0, 0.89, DinoSpecies.Diet.CARNIVORE, DinoSpecies.Diet.CARNIVORE),
			"肉食目标 0.89 < 1.0×0.9 应可猎食")
	check(not CombatRules.can_hunt(1.0, 0.9, DinoSpecies.Diet.CARNIVORE, DinoSpecies.Diet.CARNIVORE),
			"肉食目标 0.9 = 1.0×0.9 不应可猎食（严格小于）")
	check(CombatRules.can_hunt(1.0, 2.0, DinoSpecies.Diet.CARNIVORE, DinoSpecies.Diet.HERBIVORE),
			"草食目标即使更大也应可猎食")
	check(not CombatRules.can_hunt(1.0, 2.0, DinoSpecies.Diet.HERBIVORE, DinoSpecies.Diet.HERBIVORE),
			"草食攻击者不应猎食")

	# 反击：攻击者 <= 自己 ×0.9
	check(CombatRules.can_counter(0.9, 1.0), "攻击者 0.9 应可反击")
	check(not CombatRules.can_counter(0.91, 1.0), "攻击者 0.91 不应可反击")
	check(CombatRules.can_counter(0.45, 0.5), "攻击者 0.45 对 0.5 应可反击")

	# 咬击伤害：成长 / 集群 / 冲锋取整顺序
	check(CombatRules.bite_damage(20, 1.5, false, 0.0) == 30, "20×1.5 应得 30")
	check(CombatRules.bite_damage(20, 1.5, true, 0.0) == 66, "30×2.2 应得 66")
	check(CombatRules.bite_damage(10, 1.0, false, 0.2) == 12, "10+20% 集群应得 12")
	check(CombatRules.bite_damage(20, 1.5, false, 0.2) == 36, "30+20% 集群应得 36")
	check(CombatRules.bite_damage(20, 1.5, true, 0.2) == 79, "36×2.2=79.2 应四舍五入为 79")
	check(CombatRules.bite_damage(7, 1.0, false, 0.2) == 8, "7+20%=8.4 应四舍五入为 8")

	# 减伤 / 额外倍率
	check(CombatRules.apply_defense(100) == 55, "100 点伤害经重甲应剩 55")
	check(CombatRules.apply_defense(9) == 5, "9×0.55=4.95 应四舍五入为 5")
	check(CombatRules.apply_multiplier(12, 1.3) == 16, "12×1.3=15.6 应四舍五入为 16")

	# 猎物弱小 / 威胁阈值
	check(CombatRules.is_weak_prey(0.69, 1.0), "0.69 < 1.0×0.7 应为弱小猎物")
	check(not CombatRules.is_weak_prey(0.7, 1.0), "0.7 = 1.0×0.7 不应为弱小猎物")
	check(CombatRules.is_threat(0.86, 1.0), "0.86 > 1.0×0.85 应构成威胁")
	check(not CombatRules.is_threat(0.85, 1.0), "0.85 = 1.0×0.85 不应构成威胁")


# --- GrowthRules：成长规则纯逻辑 ---------------------------------------------

func _test_growth_rules() -> void:
	# 阶段倍率：越界钳制 + 非法 key 回退 1.0
	check(GrowthRules.stage_multiplier(-1, "hp") == 0.50, "阶段 -1 应钳制到幼体 hp=0.50")
	check(GrowthRules.stage_multiplier(0, "size") == 0.55, "幼体 size 应为 0.55")
	check(GrowthRules.stage_multiplier(3, "dmg") == 1.15, "成体 dmg 应为 1.15")
	check(GrowthRules.stage_multiplier(DinoSpecies.MAX_STAGE, "hp") == 1.50, "霸主 hp 应为 1.50")
	check(GrowthRules.stage_multiplier(99, "hp") == 1.50, "阶段 99 应钳制到霸主 hp=1.50")
	check(GrowthRules.stage_multiplier(0, "not_a_key") == 1.0, "非法 key 应回退 1.0")

	# 下一阶段所需进度
	check(GrowthRules.next_stage_progress(0) == 4.0, "幼体 need 应为 4")
	check(GrowthRules.next_stage_progress(1) == 7.0, "少年 need 应为 7")
	check(GrowthRules.next_stage_progress(2) == 11.0, "亚成体 need 应为 11")
	check(GrowthRules.next_stage_progress(3) == 16.0, "成体 need 应为 16")
	check(GrowthRules.next_stage_progress(DinoSpecies.MAX_STAGE) == 999999.0,
			"霸主无下一阶段，应返回占位大数 999999")
	check(GrowthRules.next_stage_progress(-1) == 4.0, "阶段 -1 的 need 应钳制到 4")
	check(GrowthRules.next_stage_progress(99) == 999999.0, "阶段 99 的 need 应钳制到霸主")

	# 累计进度 → 阶段边界（need 4/7/11/16，累计 38 到达霸主）
	check(GrowthRules.stage_index_for_progress(-1.0) == 0, "负进度应回退阶段 0")
	check(GrowthRules.stage_index_for_progress(0.0) == 0, "进度 0 应为阶段 0")
	check(GrowthRules.stage_index_for_progress(3.9) == 0, "进度 3.9 仍为阶段 0")
	check(GrowthRules.stage_index_for_progress(4.0) == 1, "进度 4 应进入阶段 1")
	check(GrowthRules.stage_index_for_progress(10.9) == 1, "进度 10.9 仍为阶段 1")
	check(GrowthRules.stage_index_for_progress(11.0) == 2, "进度 11 应进入阶段 2")
	check(GrowthRules.stage_index_for_progress(21.9) == 2, "进度 21.9 仍为阶段 2")
	check(GrowthRules.stage_index_for_progress(22.0) == 3, "进度 22 应进入阶段 3")
	check(GrowthRules.stage_index_for_progress(37.9) == 3, "进度 37.9 仍为阶段 3")
	check(GrowthRules.stage_index_for_progress(38.0) == DinoSpecies.MAX_STAGE,
			"进度 38 应进入霸主")
	check(GrowthRules.stage_index_for_progress(9999.0) == DinoSpecies.MAX_STAGE,
			"超界进度应钳制到霸主")

	# 进度累加：肉 / 植物 / 击杀当前均为 +1 格
	check(GrowthRules.add_progress(0.0, GrowthRules.MEAL_MEAT) == 1.0, "吃肉应从 0 +1 格")
	check(GrowthRules.add_progress(3.0, GrowthRules.MEAL_PLANT) == 4.0, "吃植物应从 3 +1 格")
	check(GrowthRules.add_progress(4.0, GrowthRules.MEAL_KILL) == 5.0, "击杀当前也 +1 格")
	check(GrowthRules.add_progress(6.5, GrowthRules.MEAL_MEAT) == 7.5, "累加应保留小数")
