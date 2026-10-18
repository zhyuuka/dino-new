class_name SaveManager
extends RefCounted
## 本地存档：把玩家当前物种、成长阶段、代际、最佳成绩写入 user://save.json
## 这样“死了保留成长、一直升级”才能跨局（甚至跨 App 关闭）保留。

const SAVE_PATH := "user://save.json"

## 存档格式版本：高于此版本的存档（未来格式）视为不兼容，直接回退默认
const SAVE_VERSION := 1

## 读取存档；无文件或损坏返回空字典
static func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return _ensure_defaults({})
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return _ensure_defaults({})
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return _ensure_defaults({})
	# 未来版本存档（save_version 高于当前）视为不兼容，回退默认值
	if int(parsed.get("save_version", 0)) > SAVE_VERSION:
		return _ensure_defaults({})
	return _ensure_defaults(parsed)


## 补默认值：地图 id 缺省为森林谷地
static func _ensure_defaults(d: Dictionary) -> Dictionary:
	if not d.has("map_id"):
		d["map_id"] = Maps.DEFAULT_MAP_ID
	return d

## 写入存档（原子写：先写临时文件再重命名覆盖，避免写一半导致存档损坏）
static func write_save(d: Dictionary) -> void:
	d["save_version"] = SAVE_VERSION
	var tmp_path := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()
	# 重命名失败时清理临时文件，不留垃圾 tmp
	if DirAccess.rename_absolute(tmp_path, SAVE_PATH) != OK:
		DirAccess.remove_absolute(tmp_path)

## 是否存在存档
static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## 是否存在“可用”存档（至少含物种 id 与成长阶段）
static func has_progress() -> bool:
	var d := load_save()
	return d.has("species_id") and d.has("growth_stage")
