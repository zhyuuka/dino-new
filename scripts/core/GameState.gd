extends Node
## 全局设置中心：管理用户设置（音量/灵敏度）并持久化到 user://settings.json
## 读取时逐键校验类型与范围，损坏/非法值一律回退默认，保证永不因坏存档崩溃。

const SETTINGS_PATH := "user://settings.json"

## 默认设置：音量为线性值 0.0~1.0；视角灵敏度为倍率 0.2~3.0
const DEFAULT_SETTINGS := {
	"master_volume": 1.0,   # 总音量 0.0~1.0
	"sfx_volume": 1.0,      # 音效音量 0.0~1.0
	"ambient_volume": 1.0,  # 环境音音量 0.0~1.0
	"look_sensitivity": 1.0,  # 视角灵敏度倍率 0.2~3.0
}

## 各设置键的合法范围：音量 0..1，灵敏度 0.2..3.0
const VOLUME_RANGE := Vector2(0.0, 1.0)
const SENSITIVITY_RANGE := Vector2(0.2, 3.0)

## 当前生效的设置（_ready 时从磁盘加载，非法值已回退默认）
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()


func _ready() -> void:
	_load_settings()


## 更新单键并立即落盘；非法键忽略
func set_setting(key: String, value: Variant) -> void:
	if not DEFAULT_SETTINGS.has(key):
		return
	settings[key] = value
	_save_settings()


## 便捷读取：键不存在时返回 fallback（默认 null）
func get_setting(key: String, fallback: Variant = null) -> Variant:
	return settings.get(key, fallback)


## 读取 JSON 设置；文件缺失/损坏/值非法时逐键回退默认
func _load_settings() -> void:
	# 先整体重置为默认，之后逐键用合法值覆盖
	settings = DEFAULT_SETTINGS.duplicate()
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return
	# 逐键校验类型与范围：仅接受数值，越界 clamp，非法保持默认
	for key: String in DEFAULT_SETTINGS.keys():
		if not parsed.has(key):
			continue
		var v: Variant = parsed[key]
		if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
			continue
		var range_limit: Vector2 = SENSITIVITY_RANGE if key == "look_sensitivity" else VOLUME_RANGE
		settings[key] = clampf(float(v), range_limit.x, range_limit.y)


## 原子写设置：先写临时文件再重命名覆盖，避免写一半导致设置损坏
func _save_settings() -> void:
	var tmp_path := SETTINGS_PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(settings))
	f.close()
	# 重命名失败时清理临时文件，不留垃圾 tmp
	if DirAccess.rename_absolute(tmp_path, SETTINGS_PATH) != OK:
		DirAccess.remove_absolute(tmp_path)
