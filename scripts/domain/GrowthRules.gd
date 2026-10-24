class_name GrowthRules
extends RefCounted
## 成长规则纯逻辑层：阶段数值倍率、阶段边界与进度累加。
##
## 数据源统一取 DinoSpecies.GROWTH_STAGES（纯静态数据类，不依赖场景树），
## 本类不持有节点状态，PlayerDino / AIDino 只把当前 stage / progress 传进来。

# 食物类型（与原 _eat_meal 的 kind 语义对齐）
const MEAL_MEAT: int = 0
const MEAL_PLANT: int = 1
const MEAL_KILL: int = 2

# 每次进食累加的进度格数（原实现 growth_meals += 1）
const MEAL_PROGRESS: float = 1.0


## 阶段数值倍率：hp / dmg / spd / size；非法 key 返回 1.0（不参与缩放）
## stage 越界时由 DinoSpecies.stage_info 钳制到 [0, MAX_STAGE]
static func stage_multiplier(stage: int, key: String) -> float:
	var info: Dictionary = DinoSpecies.stage_info(stage)
	var value: Variant = info.get(key, 1.0)
	if value is int or value is float:
		return float(value)
	return 1.0


## 当前阶段升到下一阶段所需的进度（即原表 need）；MAX 阶段无下一阶段，返回占位大数
static func next_stage_progress(stage: int) -> float:
	return float(DinoSpecies.stage_info(stage)["need"])


## 由“累计进食格数”反推阶段下标：跨阶段累加，越界钳制到 [0, MAX_STAGE]
## 例：need = [4, 7, 11, 16] → 0~3 格=幼体，4~10=少年，11~21=亚成体，22~37=成体，>=38=霸主
static func stage_index_for_progress(progress: float) -> int:
	var remaining: float = maxf(progress, 0.0)
	for i in DinoSpecies.MAX_STAGE:
		var need: float = next_stage_progress(i)
		if remaining < need:
			return i
		remaining -= need
	return DinoSpecies.MAX_STAGE


## 进度累加：返回 current + 本次进食格数
## 现版本肉类 / 植物 / 击杀均 +1 格（kill_made 信号全项目无 emit，击杀不直接加成长），
## 保留 meal_kind 分支是为将来“击杀加速”只改本函数即可，不改变现有平衡
static func add_progress(current: float, meal_kind: int) -> float:
	var step: float = MEAL_PROGRESS
	match meal_kind:
		MEAL_MEAT:
			step = MEAL_PROGRESS
		MEAL_PLANT:
			step = MEAL_PROGRESS
		MEAL_KILL:
			step = MEAL_PROGRESS
	return current + step
