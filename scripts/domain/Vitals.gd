class_name Vitals
extends RefCounted
## 生存数值纯逻辑层：饥饿 / 口渴 / 体力 + 饮水 / 进食 / 饿死与渴死伤害。
##
## 设计约束：
## - 不访问 get_tree() / Input / Time / randf()，时间由调用方以 delta 传入，可脱机测试
## - 所有速率、间隔、回复量、上限均通过 setup() 注入，本类不硬编码任何平衡数值
## - 整数状态（hunger/thirst/stamina）与原始 Node 版本逐项等价：小数部分留在内部累加器，
##   累满 1 点才结算整数增减，长时间平均速率不受物理步长取整影响
##
## rates 必须包含以下键（缺键会直接报错，避免静默用错默认值）：
##   hunger_interval: float          饥饿每掉 1 点所需秒数
##   thirst_interval: float          口渴每掉 1 点所需秒数（未冲刺基准）
##   thirst_sprint_mult: float       冲刺时口渴间隔倍率（0.5 = 消耗翻倍）
##   stamina_drain: float            冲刺每秒体力消耗（正数）
##   stamina_regen: float            不冲刺每秒体力回复
##   stamina_lock: float             力竭锁：体力回满到该值前不能冲刺
##   drag_stamina_mult: float        叼尸移动时体力消耗倍率
##   drink_rate: float               饮水每秒回复口渴
##   starve_interval: float          饥饿为 0 时掉血间隔
##   starve_damage: int              饥饿为 0 时每次掉血量
##   thirst_starve_interval: float   口渴为 0 时掉血间隔（<=0 表示不结算，AI 用）
##   thirst_starve_damage: int       口渴为 0 时每次掉血量
##   eat_meat_hunger: int            吃肉回复饥饿
##   eat_plant_hunger: int           吃植物回复饥饿
##   eat_plant_thirst: int           吃植物回复口渴
##   eat_egg_hunger: int             偷蛋每口回复饥饿
##   survival_step_once: bool        true = 沿用 AIDino 的秒表模式（每帧最多掉 1 点）；
##                                   false = PlayerDino 的小数累加模式（大 delta 可一次掉多点）

## 整数状态（只读给外部；变更请走本类方法，保证信号/脏标记一致）
var hunger: int = 0
var thirst: int = 0
var stamina: int = 0
var max_hunger: int = 0
var max_thirst: int = 0
var max_stamina: int = 0

var _rates: Dictionary = {}

# 小数累加器：速率 × delta 不足 1 点的余数留在这里，不丢失
var _hunger_acc: float = 0.0
var _thirst_acc: float = 0.0
var _stamina_acc: float = 0.0
var _drink_acc: float = 0.0

# AI 秒表模式专用：与旧 AIDino.hunger_timer / thirst_timer 逐帧相减完全一致
var _hunger_timer: float = 0.0
var _thirst_timer: float = 0.0

# 饿死 / 渴死计时与待结算伤害（由 Node 拉取后调用 take_damage，保持死亡流程在 Node）
var _starve_timer: float = 0.0
var _thirst_starve_timer: float = 0.0
var _pending_starve_damage: int = 0
var _pending_thirst_damage: int = 0

# 力竭锁：体力 <=0 置位，回满到 stamina_lock 才解除（与原 _exhausted 一致）
var _exhausted: bool = false

# 本次 tick 是否发生了整数变化
var _changed: bool = false


## 注入上限与速率并重置到满状态
func setup(p_max_hunger: int, p_max_thirst: int, p_max_stamina: int, rates: Dictionary) -> void:
	max_hunger = p_max_hunger
	max_thirst = p_max_thirst
	max_stamina = p_max_stamina
	_rates = rates.duplicate()
	hunger = max_hunger
	thirst = max_thirst
	stamina = max_stamina
	_hunger_acc = 0.0
	_thirst_acc = 0.0
	_stamina_acc = 0.0
	_drink_acc = 0.0
	_hunger_timer = 0.0
	_thirst_timer = 0.0
	_starve_timer = 0.0
	_thirst_starve_timer = 0.0
	_pending_starve_damage = 0
	_pending_thirst_damage = 0
	_exhausted = false
	_changed = false


## 一次完整结算：体力 + 生存衰减。供单测 / 无拆分需求的调用方使用
func tick(delta: float, sprinting: bool, dragging: bool) -> void:
	_changed = false
	_tick_stamina(delta, sprinting, dragging)
	_tick_survival(delta, sprinting)


## 仅结算体力：PlayerDino 需要保持“先体力、后口渴”的原始帧内顺序
func tick_stamina(delta: float, sprinting: bool, dragging: bool) -> void:
	_changed = false
	_tick_stamina(delta, sprinting, dragging)


## 仅结算饥饿 / 口渴 / 饿死渴死：PlayerDino 在帧尾调用，AIDino 直接使用
func tick_survival(delta: float, sprinting: bool) -> void:
	_changed = false
	_tick_survival(delta, sprinting)


## 本次 tick 是否发生整数变化（只反映最近一次 tick/tick_stamina/tick_survival）
func has_changed() -> bool:
	return _changed


## 当前完整状态快照（单测 / 存档展示用）
func get_state() -> Dictionary:
	return {
		"hunger": hunger,
		"thirst": thirst,
		"stamina": stamina,
		"max_hunger": max_hunger,
		"max_thirst": max_thirst,
		"max_stamina": max_stamina,
	}


## 饮水：按 drink_rate 每秒累积，满 1 点才加到口渴上（与原 _drink_acc 等价）
func drink(delta: float) -> void:
	_drink_acc += _rate_f("drink_rate") * delta
	if _drink_acc >= 1.0:
		var gain: int = int(_drink_acc)
		_drink_acc -= float(gain)
		_set_thirst(thirst + gain)


## 进食：kind 为 meat / plant / egg；回复量由 rates 注入
func eat(kind: String) -> void:
	match kind:
		"meat":
			_add_hunger(_rate_i("eat_meat_hunger"))
		"plant":
			_add_hunger(_rate_i("eat_plant_hunger"))
			_add_thirst(_rate_i("eat_plant_thirst"))
		"egg":
			_add_hunger(_rate_i("eat_egg_hunger"))


## 巢穴等场景直接回体力
func restore_stamina(amount: int) -> void:
	_set_stamina(stamina + amount)


## 产蛋等场景直接扣饥饿
func consume_hunger(amount: int) -> void:
	_set_hunger(maxi(0, hunger - amount))


## 拉取并清零“饿死”待结算伤害，由 Node 调 take_damage
func pull_starve_damage() -> int:
	var dmg: int = _pending_starve_damage
	_pending_starve_damage = 0
	return dmg


## 拉取并清零“渴死”待结算伤害，由 Node 调 take_damage
func pull_thirst_damage() -> int:
	var dmg: int = _pending_thirst_damage
	_pending_thirst_damage = 0
	return dmg


## 是否允许冲刺：有体力且未处于力竭锁
func can_sprint() -> bool:
	return stamina > 0 and not _exhausted


## 是否力竭锁中
func is_exhausted() -> bool:
	return _exhausted


# ================= 内部结算 =================

func _tick_survival(delta: float, sprinting: bool) -> void:
	var hunger_interval: float = _rate_f("hunger_interval")
	if _rate_b("survival_step_once"):
		# AI 旧实现：秒表累加，每跨过一个间隔只掉 1 点（大 delta 下也不会一次扣多）
		_hunger_timer += delta
		if _hunger_timer >= hunger_interval:
			_hunger_timer -= hunger_interval
			_subtract_hunger(1)
	else:
		# Player 旧实现：delta / 间隔 累加，满 1 点扣 1 点，余数保留（大 delta 可一次扣多）
		_hunger_acc += delta / hunger_interval
		if _hunger_acc >= 1.0:
			var h: int = int(_hunger_acc)
			_hunger_acc -= float(h)
			_subtract_hunger(h)
	if hunger <= 0:
		var starve_interval: float = _rate_f("starve_interval")
		_starve_timer += delta
		if _starve_timer >= starve_interval:
			_starve_timer -= starve_interval
			_pending_starve_damage += _rate_i("starve_damage")
	# 口渴：冲刺时间隔 × thirst_sprint_mult（0.5 → 消耗翻倍）
	var thirst_interval: float = _rate_f("thirst_interval")
	if sprinting:
		thirst_interval *= _rate_f("thirst_sprint_mult")
	if _rate_b("survival_step_once"):
		_thirst_timer += delta
		if _thirst_timer >= thirst_interval:
			_thirst_timer -= thirst_interval
			_subtract_thirst(1)
	else:
		_thirst_acc += delta / thirst_interval
		if _thirst_acc >= 1.0:
			var t: int = int(_thirst_acc)
			_thirst_acc -= float(t)
			_subtract_thirst(t)
	var thirst_starve_interval: float = _rate_f("thirst_starve_interval")
	if thirst <= 0 and thirst_starve_interval > 0.0:
		_thirst_starve_timer += delta
		if _thirst_starve_timer >= thirst_starve_interval:
			_thirst_starve_timer -= thirst_starve_interval
			_pending_thirst_damage += _rate_i("thirst_starve_damage")


func _tick_stamina(delta: float, sprinting: bool, dragging: bool) -> void:
	# 每秒变化率：负 = 消耗，正 = 回复。叼尸移动按 drag_stamina_mult 倍流失；原地叼住按常规回复
	var rate: float = _rate_f("stamina_regen")
	if dragging:
		rate = -_rate_f("stamina_drain") * _rate_f("drag_stamina_mult")
	elif sprinting:
		rate = -_rate_f("stamina_drain")
	_stamina_acc += rate * delta
	if _stamina_acc >= 1.0:
		var gain: int = int(_stamina_acc)
		_stamina_acc -= float(gain)
		_set_stamina(stamina + gain)
	elif _stamina_acc <= -1.0:
		var loss: int = int(_stamina_acc)   # int() 向零截断，不足 1 点的余数继续保留
		_stamina_acc -= float(loss)
		_set_stamina(stamina + loss)
	_update_exhausted()


func _update_exhausted() -> void:
	if stamina <= 0:
		_exhausted = true
	elif float(stamina) >= _rate_f("stamina_lock"):
		_exhausted = false


func _add_hunger(amount: int) -> void:
	_set_hunger(clampi(hunger + amount, 0, max_hunger))


func _subtract_hunger(amount: int) -> void:
	_set_hunger(maxi(0, hunger - amount))


func _add_thirst(amount: int) -> void:
	_set_thirst(clampi(thirst + amount, 0, max_thirst))


func _subtract_thirst(amount: int) -> void:
	_set_thirst(maxi(0, thirst - amount))


func _set_hunger(value: int) -> void:
	var next: int = clampi(value, 0, max_hunger)
	if next != hunger:
		hunger = next
		_changed = true


func _set_thirst(value: int) -> void:
	var next: int = clampi(value, 0, max_thirst)
	if next != thirst:
		thirst = next
		_changed = true


func _set_stamina(value: int) -> void:
	var next: int = clampi(value, 0, max_stamina)
	if next != stamina:
		stamina = next
		_changed = true


func _rate_f(key: String) -> float:
	return float(_rates[key])


func _rate_i(key: String) -> int:
	return int(_rates[key])


func _rate_b(key: String) -> bool:
	return bool(_rates[key])
