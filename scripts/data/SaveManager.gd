class_name SaveManager
extends RefCounted
## 本地存档：把玩家当前物种、成长阶段、代际、最佳成绩写入 user://save.json
## 这样“死了保留成长、一直升级”才能跨局（甚至跨 App 关闭）保留。

const SAVE_PATH := "user://save.json"

## 读取存档；无文件或损坏返回空字典
static func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed

## 写入存档
static func write_save(d: Dictionary) -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()

## 是否存在存档
static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

## 是否存在“可用”存档（至少含物种 id 与成长阶段）
static func has_progress() -> bool:
	var d := load_save()
	return d.has("species_id") and d.has("growth_stage")
