extends Node
## 全局成就中心（autoload：Achievements）：定义 8 项成就，记录解锁状态并持久化，
## 同时承载"新手引导已完成"的跨局标记（TutorialGuide 完成后写入，存档跨局不再显示引导）。
## Main 侧调用 unlock(id) 触发；HUD 连接 achievement_unlocked 弹横幅；
## PauseMenu 成就页读取 all() 展示列表。
## 持久化风格与 GameState 一致：JSON + 原子写（先写 .tmp 再重命名覆盖），
## 读取时逐字段校验类型，损坏/非法值一律丢弃，保证永不因坏存档崩溃。

const SAVE_PATH := "user://achievements.json"

## 成就定义表（有序：暂停菜单成就页按此顺序展示）
## id 与 Main 侧调用 Achievements.unlock(id) 的触发点一一对应
const DEFS: Array[Dictionary] = [
	{"id": "first_kill", "title": "初次狩猎", "desc": "第一次猎杀一只恐龙"},
	{"id": "kills_10", "title": "老练猎手", "desc": "累计猎杀 10 只"},
	{"id": "survival_300", "title": "活过五分钟", "desc": "单代存活 300 秒"},
	{"id": "evolution_2", "title": "二阶进化", "desc": "成长到第二阶段"},
	{"id": "evolution_max", "title": "完全体", "desc": "成长到最高阶段"},
	{"id": "nest_first", "title": "第一次产蛋", "desc": "在巢穴产下自己的蛋"},
	{"id": "herd_witness", "title": "迁徙见证者", "desc": "目睹一次兽群迁徙"},
	{"id": "storm_survivor", "title": "风暴幸存者", "desc": "在风暴中存活"},
]

## 引导完成标记在 JSON 中的键名
const TUTORIAL_KEY := "tutorial_done"

## 首次解锁某成就时发出（HUD 连接后弹横幅；幂等解锁不重复发出）
signal achievement_unlocked(id: String, title: String)

## 已解锁的成就 id 集合（只存已解锁项，未列出的即未解锁）
var _unlocked: Dictionary = {}

## 新手引导是否已完成（跨局持久标记）
var _tutorial_done: bool = false


func _ready() -> void:
	_load()


## 解锁成就（幂等）：首次解锁时持久化并发信号；未知 id 忽略（防调用方拼写错误写坏存档）
func unlock(id: String) -> void:
	if _unlocked.has(id):
		return
	var def: Dictionary = _def(id)
	if def.is_empty():
		return
	_unlocked[id] = true
	_save()
	achievement_unlocked.emit(id, String(def["title"]))


## 指定成就是否已解锁
func is_unlocked(id: String) -> bool:
	return _unlocked.has(id)


## 全部成就状态表：id -> {"title": String, "desc": String, "unlocked": bool}
func all() -> Dictionary:
	var out: Dictionary = {}
	for def: Dictionary in DEFS:
		out[String(def["id"])] = {
			"title": String(def["title"]),
			"desc": String(def["desc"]),
			"unlocked": _unlocked.has(String(def["id"])),
		}
	return out


## 新手引导是否已完成（跨局存档）
func is_tutorial_done() -> bool:
	return _tutorial_done


## 标记新手引导完成并持久化（幂等）
func mark_tutorial_done() -> void:
	if _tutorial_done:
		return
	_tutorial_done = true
	_save()


## 按 id 查成就定义；未知 id 返回空字典
func _def(id: String) -> Dictionary:
	for def: Dictionary in DEFS:
		if String(def["id"]) == id:
			return def
	return {}


## 读取成就存档：文件缺失/损坏/字段类型非法时整体回退未解锁状态
func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var t: Variant = d.get(TUTORIAL_KEY, false)
	if typeof(t) == TYPE_BOOL:
		_tutorial_done = t
	var arr: Variant = d.get("unlocked", [])
	if typeof(arr) != TYPE_ARRAY:
		return
	# 逐条校验：仅接受字符串且必须命中成就定义表，未知 id 丢弃
	for id_v: Variant in arr as Array:
		if typeof(id_v) == TYPE_STRING and not _def(String(id_v)).is_empty():
			_unlocked[String(id_v)] = true


## 原子写存档：先写临时文件再重命名覆盖，避免写一半导致存档损坏
func _save() -> void:
	var payload := {"unlocked": _unlocked.keys(), TUTORIAL_KEY: _tutorial_done}
	var tmp_path := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(payload))
	f.close()
	# 重命名失败时清理临时文件，不留垃圾 tmp
	if DirAccess.rename_absolute(tmp_path, SAVE_PATH) != OK:
		DirAccess.remove_absolute(tmp_path)
