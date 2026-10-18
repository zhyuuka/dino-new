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
	_test_maps()
	_test_dino_species()
	_test_save_manager()
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


# --- SaveManager：本地存档 ---------------------------------------------------

## 直接覆写原始文件（模拟损坏档 / 未来版本档）
func _write_raw(path: String, content: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		check(false, "测试准备失败：无法写入 " + path)
		return
	f.store_string(content)
	f.close()


## 删除 user:// 下指定文件（保证测试确定性）
func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _test_save_manager() -> void:
	# 清场：删除可能残留的存档与 tmp，保证从“无档”状态开始
	_remove_file(SaveManager.SAVE_PATH)
	_remove_file(SaveManager.SAVE_PATH + ".tmp")

	# 1) 无档状态
	check(not SaveManager.has_save(), "无档时 has_save() 应为 false")
	check(not SaveManager.has_progress(), "无档时 has_progress() 应为 false")
	var empty: Dictionary = SaveManager.load_save()
	check(empty.get("map_id", "") == Maps.DEFAULT_MAP_ID, "无档时 load_save() 应回退默认 map_id")

	# 2) roundtrip：写入后读回全字段一致（SAVE_PATH 是常量 user://save.json，测试直接读写同一文件）
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
	check(int(loaded.get("save_version", -1)) == SaveManager.SAVE_VERSION, "save_version 应为 1")
	for field in ["species_id", "growth_stage", "generation", "map_id", "best_time", "best_kills"]:
		check(loaded.get(field) == payload[field], "roundtrip 字段 %s 应一致" % field)
	check(not FileAccess.file_exists(SaveManager.SAVE_PATH + ".tmp"), "write_save 后不应残留 tmp 文件")
	check(SaveManager.has_progress(), "完整存档时 has_progress() 应为 true")

	# 3) 缺物种信息的档：has_save 为 true 但 has_progress 为 false
	SaveManager.write_save({"map_id": "snow"})
	check(SaveManager.has_save(), "写入部分档后 has_save() 应为 true")
	check(not SaveManager.has_progress(), "缺 species_id 时 has_progress() 应为 false")

	# 4) 损坏档：非法 JSON → 回退默认
	_write_raw(SaveManager.SAVE_PATH, "not json{{")
	check(SaveManager.has_save(), "损坏档文件存在时 has_save() 应为 true")
	var corrupt: Dictionary = SaveManager.load_save()
	check(corrupt.get("map_id", "") == Maps.DEFAULT_MAP_ID, "损坏档 load_save() 应回退默认 map_id")
	check(not corrupt.has("species_id"), "损坏档不应残留 species_id")
	check(not SaveManager.has_progress(), "损坏档 has_progress() 应为 false")

	# 5) 未来版本档：save_version 高于当前 → 回退默认
	_write_raw(SaveManager.SAVE_PATH, JSON.stringify({"save_version": 99, "species_id": "trex"}))
	var future: Dictionary = SaveManager.load_save()
	check(not future.has("species_id"), "未来版本档应被回退默认（species_id 不存在）")
	check(future.get("map_id", "") == Maps.DEFAULT_MAP_ID, "未来版本档回退后 map_id 应为默认值")
