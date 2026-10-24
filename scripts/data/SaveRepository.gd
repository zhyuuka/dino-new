class_name SaveRepository
extends RefCounted
## 存档唯一的磁盘 IO 入口（静态类）：
## - 单文件 JSON：user://save.json（与旧 SaveManager 路径一致，升级不搬档）
## - 显式版本迁移链：v1 → v2 →（预留）v3
## - 原子写（tmp + 回读校验 + rename）、写前轮换备份、损坏/未来版本隔离
## 规则：
## 1) 所有 IO 失败只返回 false / 默认值，绝不抛错、绝不删除玩家原始档
## 2) 未来版本档（save_version > SAVE_VERSION）只隔离 + 返回默认档，不静默覆盖
## 3) 迁移成功后立刻落盘到当前版本，保证下次读取不再走迁移
## 4) 键名常量见 PlayerProfile；本类只额外负责 save_version / profile_version

## 存档文件路径（旧格式与新格式共用，避免玩家升级后丢档）
const SAVE_PATH := "user://save.json"
## 上一份有效档（仅在现有内容有效时轮换）
const BAK_PATH := "user://save.bak"
## 未来版本档隔离副本
const FUTURE_BAK_PATH := "user://save.future.bak"
## 损坏档隔离副本
const CORRUPT_BAK_PATH := "user://save.corrupt.bak"

## 当前存档结构版本：v1 = 旧格式（无 profile_version，字段键相同）；v2 = 显式标记结构版本
const SAVE_VERSION: int = 2

## 仓库信封版本（判断能否读懂这份档）
const KEY_SAVE_VERSION := "save_version"
## 结构版本（v2 起与 save_version 同步；v1 旧档没有这个键）
const KEY_PROFILE_VERSION := "profile_version"


## 读档：解析 → 版本判断 → 迁移 → 类型化快照。任何异常路径都返回默认档
static func load_profile() -> PlayerProfile:
	if not FileAccess.file_exists(SAVE_PATH):
		return PlayerProfile.defaults()

	var d: Dictionary = _read_json(SAVE_PATH)
	if d.is_empty():
		# 非 JSON / 非字典 / 空档：保留现场后回退默认
		_backup(SAVE_PATH, CORRUPT_BAK_PATH)
		return PlayerProfile.defaults()

	var from_version: int = int(d.get(KEY_SAVE_VERSION, 1))
	if from_version > SAVE_VERSION:
		# 未来版本：备份副本后回退默认，原文件保留（玩家换回新版本仍能读到）
		_backup(SAVE_PATH, FUTURE_BAK_PATH)
		push_warning("SaveRepository: 存档版本 v%d 高于当前 v%d，已隔离为 save.future.bak" % [from_version, SAVE_VERSION])
		return PlayerProfile.defaults()
	if from_version < 1:
		# 极早期档（无版本键或写成 0）统一按 v1 处理
		from_version = 1

	var migrated: Dictionary = _migrate(d, from_version)
	if migrated.is_empty():
		# 迁移链缺步骤 / 迁移结果非法：按损坏档处理，保留现场
		_backup(SAVE_PATH, CORRUPT_BAK_PATH)
		push_warning("SaveRepository: v%d 存档迁移失败，已隔离为 save.corrupt.bak" % from_version)
		return PlayerProfile.defaults()

	# 迁移即落盘：把 v1 档就地升级为当前版本，避免每次启动重复迁移
	if from_version < SAVE_VERSION:
		_write_dict(migrated)

	return PlayerProfile.from_dict(migrated)


## 写档：提交完整快照（不读改写），原子替换；返回是否成功
static func save_profile(p: PlayerProfile) -> bool:
	if p == null:
		return false

	var d: Dictionary = p.to_dict()
	d[KEY_SAVE_VERSION] = SAVE_VERSION
	d[KEY_PROFILE_VERSION] = SAVE_VERSION
	return _write_dict(d)


## 是否存在存档文件（不等价于“可用进度”，损坏档也算存在）
static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 是否存在可用进度：文件存在、JSON 可解析且含物种与成长字段，版本不高于当前
static func has_progress() -> bool:
	var d: Dictionary = _read_json(SAVE_PATH)
	if d.is_empty():
		return false
	if int(d.get(KEY_SAVE_VERSION, 1)) > SAVE_VERSION:
		return false
	return d.has(PlayerProfile.KEY_SPECIES) and d.has(PlayerProfile.KEY_GROWTH_STAGE)


# ================= 迁移链 =================

## 逐级迁移：每步只负责 vN → vN+1；缺失步骤 fail closed（宁可回退备份，不做猜测性迁移）
static func _migrate(d: Dictionary, from_version: int) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var version: int = from_version
	while version < SAVE_VERSION:
		match version:
			1:
				out = _migrate_v1_to_v2(out)
			_:
				push_warning("SaveRepository: 缺少 v%d→v%d 迁移步骤" % [version, version + 1])
				return {}
		if out.is_empty():
			return {}
		version += 1
		out[KEY_SAVE_VERSION] = version
		out[KEY_PROFILE_VERSION] = version
	return out


## v1 → v2：只补默认字段与 profile_version，**不改变任何既有字段语义**。
## v1 可能是无 save_version 的旧 SaveManager 档，也可能是 save_version=1 的档，字段键完全相同。
static func _migrate_v1_to_v2(d: Dictionary) -> Dictionary:
	var out: Dictionary = d.duplicate(true)
	var base: Dictionary = PlayerProfile.defaults().to_dict()
	for key: Variant in base.keys():
		if not out.has(key):
			out[key] = base[key]
	out[KEY_SAVE_VERSION] = 2
	out[KEY_PROFILE_VERSION] = 2
	return out


## 占位：v2 → v3 尚未启用（SAVE_VERSION 仍为 2，不会走到这里）。
## 未来新增/重命名字段时：在这里补默认值或改结构，并在 _migrate 的 match 里加 `2:` 分支，
## 同时把 SAVE_VERSION 提为 3；注意此函数必须保持纯函数（duplicate 后处理，不改入参）。
static func _migrate_v2_to_v3(d: Dictionary) -> Dictionary:
	return d.duplicate(true)


# ================= 原子写与备份 =================

## 原子写：写前备份 → 写 tmp → 回读校验 → rename 覆盖
static func _write_dict(d: Dictionary) -> bool:
	# 写前备份：只有现有内容“有效且版本可读”时才轮换 save.bak，
	# 避免损坏档 / 未来版本档把上一份好备份顶掉
	if FileAccess.file_exists(SAVE_PATH) and _is_valid_content(_read_json(SAVE_PATH)):
		if not _backup(SAVE_PATH, BAK_PATH):
			push_warning("SaveRepository: 备份 save.bak 失败，已放弃本次写入")
			return false

	var text: String = JSON.stringify(d, "\t")
	var tmp_path: String = SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_warning("SaveRepository: 无法打开临时文件 %s" % tmp_path)
		return false
	f.store_string(text)
	f.flush()
	f.close()

	# 回读校验：确认落盘内容与内存一致（防截断 / 半写）
	var check := FileAccess.open(tmp_path, FileAccess.READ)
	if check == null:
		DirAccess.remove_absolute(tmp_path)
		return false
	var written: String = check.get_as_text()
	check.close()
	if written != text:
		DirAccess.remove_absolute(tmp_path)
		push_warning("SaveRepository: 临时文件回读不一致，已放弃写入")
		return false

	# 目标存在且非写保护时 rename 会覆盖（Godot 4.4 DirAccess 文档）
	if DirAccess.rename_absolute(tmp_path, SAVE_PATH) != OK:
		DirAccess.remove_absolute(tmp_path)
		return false
	return true


## 内容是否可作为“上一份有效档”：能解析成字典且版本不高于当前
static func _is_valid_content(d: Dictionary) -> bool:
	if d.is_empty():
		return false
	return int(d.get(KEY_SAVE_VERSION, 1)) <= SAVE_VERSION


## 复制备份（目标已存在则覆盖）；失败只返回 false，不抛错
static func _backup(src: String, dst: String) -> bool:
	if not FileAccess.file_exists(src):
		return false
	if FileAccess.file_exists(dst):
		DirAccess.remove_absolute(dst)
	return DirAccess.copy_absolute(src, dst) == OK


# ================= 读 JSON =================

## 读并解析 JSON；文件不存在 / 打不开 / 非字典一律返回空字典
static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text: String = f.get_as_text()
	f.close()
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = json.data
	return out
