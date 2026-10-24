class_name CombatRules
extends RefCounted
## 战斗数值纯规则层：咬击伤害、猎食/反击判定、受伤减免。
##
## 全部为 static 纯函数，不持有状态、不访问 Node / 场景树 / 输入 / 随机数，
## 阈值与倍率全部从原 PlayerDino / AIDino 内嵌公式原样提取，保证行为等价。

# 猎食判定：同体型肉食目标需小于攻击者 ×0.9 才可猎食；草食目标恒定可猎
const HUNT_RATIO: float = 0.9
# 仇恨反击：攻击者体型 <= 自己 ×0.9 视为打得过
const COUNTER_RATIO: float = 0.9
# “弱小猎物”判定：猎物 < 自己 ×0.7 时，即使不饿也会主动捕猎
const PREY_WEAK_RATIO: float = 0.7
# 威胁判定：肉食目标 > 自己 ×0.85 才构成逃跑威胁
const THREAT_RATIO: float = 0.85

# 集群伤害加成（PlayerDino / AIDino 原值一致）
const PACK_DMG_BONUS: float = 0.20
# 冲锋伤害倍率（PlayerDino 原值）
const CHARGE_DMG_MULT: float = 2.2
# 重甲被动伤害减免（PlayerDino / AIDino 原值一致）
const DEFENSE_REDUCTION: float = 0.55


## 咬击最终伤害
## - growth_mult：成长阶段伤害倍率（调用方若已把成长乘进 base，可传 1.0）
## - charge：是否冲锋（额外 ×2.2）
## - pack_bonus：集群/同伴加成（0.2 = +20%，<=0 视为无加成）
## 取整顺序与旧实现一致：先成长，再集群，最后冲锋，每步 round 后转 int
static func bite_damage(base: int, growth_mult: float, charge: bool, pack_bonus: float) -> int:
	var dmg: int = int(round(float(base) * growth_mult))
	if pack_bonus > 0.0:
		dmg = int(round(float(dmg) * (1.0 + pack_bonus)))
	if charge:
		dmg = int(round(float(dmg) * CHARGE_DMG_MULT))
	return dmg


## 猎食判定（与 AIDino._find_prey 完全一致）
## 草食目标无论体型都可猎食；肉食目标必须严格小于攻击者 ×0.9；非肉食攻击者不捕猎
static func can_hunt(attacker_size: float, target_size: float, attacker_diet: int, target_diet: int) -> bool:
	if attacker_diet != DinoSpecies.Diet.CARNIVORE:
		return false
	if target_diet == DinoSpecies.Diet.HERBIVORE:
		return true
	return target_size < attacker_size * HUNT_RATIO


## 仇恨反击判定（与 AIDino._can_beat_attacker 一致）
## attacker_size 为打人者的体型，target_size 为被攻击者（自己）的体型
static func can_counter(attacker_size: float, target_size: float) -> bool:
	return attacker_size <= target_size * COUNTER_RATIO


## 重甲等减伤：round(amount × reduction)
static func apply_defense(amount: int, reduction: float = DEFENSE_REDUCTION) -> int:
	return int(round(float(amount) * reduction))


## 限时增益等额外伤害倍率：round(amount × mult)
static func apply_multiplier(amount: int, mult: float) -> int:
	return int(round(float(amount) * mult))


## 猎物是否“弱小到不饿也要打”（与 AIDino._prey_weak 一致）
static func is_weak_prey(prey_size: float, attacker_size: float) -> bool:
	return prey_size < attacker_size * PREY_WEAK_RATIO


## 肉食目标是否构成逃跑威胁（与 AIDino._find_threat 一致）
static func is_threat(threat_size: float, self_size: float) -> bool:
	return threat_size > self_size * THREAT_RATIO
