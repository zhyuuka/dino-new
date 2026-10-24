class_name SaveManager
extends RefCounted
## 存档兼容门面（过渡期保留）：所有读写一律转发到 SaveRepository。
## 保留旧 API 只为不破坏历史调用点（Main/PlayerDino/SpeciesSelect/测试）；
## 新代码请直接使用 PlayerProfile + SaveRepository，本门面不再包含任何 IO 逻辑。
## 注意：磁盘只有一个文件 user://save.json，键名常量见 PlayerProfile / SaveRepository。

const SAVE_PATH := SaveRepository.SAVE_PATH
const SAVE_VERSION: int = SaveRepository.SAVE_VERSION


## 读取存档并转成旧字典形状（不含 save_version，由 Repository 负责）
static func load_save() -> Dictionary:
	return SaveRepository.load_profile().to_dict()


## 把旧字典写成完整快照；非法字段由 PlayerProfile.from_dict 钳制
static func write_save(d: Dictionary) -> void:
	SaveRepository.save_profile(PlayerProfile.from_dict(d))


## 是否存在存档文件（损坏档也算存在，与旧行为一致）
static func has_save() -> bool:
	return SaveRepository.has_save()


## 是否存在“可用”存档（至少含物种 id 与成长阶段；损坏/未来版本档为 false）
static func has_progress() -> bool:
	return SaveRepository.has_progress()
