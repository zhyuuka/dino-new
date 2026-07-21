class_name DinoSpecies
extends RefCounted
## 恐龙物种数据库：定义所有可玩 / AI 物种的属性、食性、招牌技能与外观
## 设计参考《诅咒之岛》（The Cursed Dinosaur Isle）：每种恐龙有独特体型、属性与技能，
## 玩家开局可选物种，AI 也按物种构成真实食物链。

# --- 食性 ---
enum Diet { CARNIVORE, HERBIVORE }

# --- 主动技能（按键触发） ---
enum ActiveAbility { NONE, CHARGE }

# --- 被动技能（始终生效） ---
enum PassiveAbility { NONE, PACK, DEFENSE, APEX }

# 成长阶段：幼体 → 少年 → 亚成体 → 成体 → 霸主
# size / hp / dmg / spd 为该阶段相对“成体基准(=1.0)”的倍率
# need = 从本阶段升到下阶段所需的“进食次数”（霸主后不再成长）
const GROWTH_STAGES: Array = [
	{ "name": "幼体",  "size": 0.55, "hp": 0.50, "dmg": 0.45, "spd": 1.05, "need": 4 },
	{ "name": "少年",  "size": 0.75, "hp": 0.70, "dmg": 0.65, "spd": 1.00, "need": 7 },
	{ "name": "亚成体", "size": 0.95, "hp": 0.90, "dmg": 0.85, "spd": 1.00, "need": 11 },
	{ "name": "成体",  "size": 1.20, "hp": 1.15, "dmg": 1.15, "spd": 0.97, "need": 16 },
	{ "name": "霸主",  "size": 1.60, "hp": 1.50, "dmg": 1.50, "spd": 0.93, "need": 999999 },
]
const MAX_STAGE: int = 4

# 物种定义对象
class SpeciesDef:
	var id: String
	var name: String
	var diet: Diet
	var active: ActiveAbility
	var passive: PassiveAbility
	var max_health: int
	var bite_damage: int
	var walk_speed: float
	var run_speed: float
	var bite_cooldown: float
	var size: float
	var body_color: Color
	var dark_color: Color
	var blurb: String

	func _init(p_id: String, p_name: String, p_diet: Diet, p_active: ActiveAbility,
			p_passive: PassiveAbility, p_hp: int, p_bite: int, p_walk: float, p_run: float,
			p_cd: float, p_size: float, p_body: Color, p_dark: Color, p_blurb: String) -> void:
		id = p_id
		name = p_name
		diet = p_diet
		active = p_active
		passive = p_passive
		max_health = p_hp
		bite_damage = p_bite
		walk_speed = p_walk
		run_speed = p_run
		bite_cooldown = p_cd
		size = p_size
		body_color = p_body
		dark_color = p_dark
		blurb = p_blurb

	func diet_text() -> String:
		return "肉食" if diet == Diet.CARNIVORE else "草食"

	func ability_text() -> String:
		var a := ""
		match active:
			ActiveAbility.CHARGE: a = "冲锋"
		match passive:
			PassiveAbility.PACK: a = ("冲锋，" if a != "" else "") + "集群"
			PassiveAbility.DEFENSE: a = (a + "，" if a != "" else "") + "重甲"
			PassiveAbility.APEX: a = (a + "，" if a != "" else "") + "威压"
		return a if a != "" else "无"

static var _db: Dictionary = {}

static func _build() -> void:
	if not _db.is_empty():
		return
	var defs := [
		SpeciesDef.new("raptor", "迅猛龙", Diet.CARNIVORE, ActiveAbility.NONE, PassiveAbility.PACK,
			70, 14, 7.5, 13.5, 0.4, 0.6,
			Color(0.85, 0.45, 0.2), Color(0.55, 0.28, 0.1),
			"敏捷小型掠食者，成群时凶猛，单体脆弱。"),
		SpeciesDef.new("carno", "食肉牛龙", Diet.CARNIVORE, ActiveAbility.CHARGE, PassiveAbility.NONE,
			140, 26, 6.5, 12.0, 0.6, 1.05,
			Color(0.82, 0.3, 0.25), Color(0.5, 0.18, 0.15),
			"中型猛兽，冲锋撞击伤害极高。"),
		SpeciesDef.new("trex", "霸王龙", Diet.CARNIVORE, ActiveAbility.NONE, PassiveAbility.APEX,
			320, 55, 5.0, 9.5, 0.9, 1.7,
			Color(0.4, 0.6, 0.3), Color(0.25, 0.4, 0.2),
			"顶级掠食者，威压令小型肉食龙逃窜。"),
		SpeciesDef.new("trike", "三角龙", Diet.HERBIVORE, ActiveAbility.CHARGE, PassiveAbility.DEFENSE,
			240, 22, 5.0, 9.0, 0.7, 1.45,
			Color(0.45, 0.55, 0.7), Color(0.3, 0.38, 0.5),
			"重甲草食，冲锋与防御兼备。"),
		SpeciesDef.new("anky", "甲龙", Diet.HERBIVORE, ActiveAbility.NONE, PassiveAbility.DEFENSE,
			260, 12, 4.0, 7.0, 0.8, 1.25,
			Color(0.55, 0.55, 0.3), Color(0.38, 0.38, 0.2),
			"移动堡垒，伤害减免极高，但速度慢。"),
		SpeciesDef.new("galli", "似鸡龙", Diet.HERBIVORE, ActiveAbility.NONE, PassiveAbility.NONE,
			55, 6, 9.0, 16.0, 0.4, 0.55,
			Color(0.8, 0.7, 0.45), Color(0.55, 0.48, 0.3),
			"极速逃跑专家，脆皮但跑得飞快。"),
	]
	for d in defs:
		_db[d.id] = d

## 返回所有物种（数组）
static func all() -> Array:
	_build()
	return _db.values()

## 按 id 取物种；找不到返回 null
static func by_id(id: String) -> SpeciesDef:
	_build()
	return _db.get(id, null)

## 成长阶段名
static func stage_name(stage: int) -> String:
	return GROWTH_STAGES[clampi(stage, 0, MAX_STAGE)]["name"]

## 成长阶段数据
static func stage_info(stage: int) -> Dictionary:
	return GROWTH_STAGES[clampi(stage, 0, MAX_STAGE)]
