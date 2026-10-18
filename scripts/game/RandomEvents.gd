class_name RandomEvents
extends Node
## 随机事件子系统：每 90~150 秒随机触发一个事件，持续 25~40 秒，
## 全程经 event_started / event_ended 信号广播横幅文案（Main 接到 hud.show_banner）。
## 事件本体通过注入的子系统引用生效（允许 null，未注入的事件不参与抽取）：
## - 兽群迁徙 → EcosystemDirector.spawn_herd（并入生态，事件结束不回收）
## - 风暴     → DayNightCycle.set_storm（雾密度 ×3 / 太阳能量 ×0.6，结束恢复）
## - 丰饶期   → FoliageSpawner.set_abundant（重生间隔 ÷4 + 立即补生 5 株，结束恢复）

signal event_started(text: String)
signal event_ended(text: String)

const EVENT_INTERVAL_MIN: float = 90.0   # 两次事件间隔下限（秒）
const EVENT_INTERVAL_MAX: float = 150.0  # 两次事件间隔上限（秒）
const EVENT_DURATION_MIN: float = 25.0   # 事件持续时长下限（秒）
const EVENT_DURATION_MAX: float = 40.0   # 事件持续时长上限（秒）
const HERD_SIZE_MIN: int = 4             # 兽群个体数下限
const HERD_SIZE_MAX: int = 6             # 兽群个体数上限

## 兽群迁徙候选物种：草食兽群成群迁徙，契合"兽群"语义
const HERD_POOL: Array[String] = [DinoSpecies.ID_GALLI, DinoSpecies.ID_TRIKE, DinoSpecies.ID_ANKY]

enum State { IDLE, ACTIVE }  # 状态机：IDLE 冷却计时 → ACTIVE 事件进行中（未结束不抽新事件）
enum EventKind { HERD, STORM, ABUNDANCE }  # 事件种类：新增事件在 _event_catalog 追加条目即可

var director: EcosystemDirector = null
var day_night: DayNightCycle = null
var foliage_spawner: FoliageSpawner = null

var _state: State = State.IDLE
var _next_timer: float = 0.0      # 距下次事件抽取的剩余秒数（IDLE 期倒数）
var _duration_timer: float = 0.0  # 当前事件剩余持续秒数（ACTIVE 期倒数）
var _active_kind: int = -1        # 进行中的事件种类（EventKind）

## 事件目录：kind + 开始/结束处理 Callable（均返回横幅文案），数据驱动便于扩展
var _event_catalog: Array[Dictionary] = []


func _ready() -> void:
	_event_catalog = [
		{"kind": EventKind.HERD, "start": _start_herd, "end": _end_herd},
		{"kind": EventKind.STORM, "start": _start_storm, "end": _end_storm},
		{"kind": EventKind.ABUNDANCE, "start": _start_abundance, "end": _end_abundance},
	]
	_next_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)


func _process(delta: float) -> void:
	match _state:
		State.IDLE:
			_next_timer -= delta
			if _next_timer <= 0.0:
				_trigger_event()
		State.ACTIVE:
			_duration_timer -= delta
			if _duration_timer <= 0.0:
				_finish_event()


## 从目录随机抽取一个"引用已注入"的事件并启动；事件进行中不会被调用（状态机保证）
func _trigger_event() -> void:
	var pool: Array[Dictionary] = []
	for ev in _event_catalog:
		if _event_available(int(ev["kind"])):
			pool.append(ev)
	if pool.is_empty():
		# 子系统引用尚未注入：本周期放弃抽取，重排冷却等待下次
		_next_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
		return
	var ev: Dictionary = pool[randi() % pool.size()]
	var text: String = String(ev["start"].call())
	if text == "":
		_next_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
		return
	_active_kind = int(ev["kind"])
	_duration_timer = randf_range(EVENT_DURATION_MIN, EVENT_DURATION_MAX)
	_state = State.ACTIVE
	event_started.emit(text)


## 事件到时收尾：执行结束处理（恢复世界效果）并广播结束横幅，回到冷却期
func _finish_event() -> void:
	var end_text: String = ""
	for ev in _event_catalog:
		if int(ev["kind"]) == _active_kind:
			end_text = String(ev["end"].call())
			break
	_state = State.IDLE
	_active_kind = -1
	_next_timer = randf_range(EVENT_INTERVAL_MIN, EVENT_INTERVAL_MAX)
	event_ended.emit(end_text)


## 事件可用性：对应子系统引用已注入才可被抽取（允许 null 判空）
func _event_available(kind: int) -> bool:
	match kind:
		EventKind.HERD:
			return director != null
		EventKind.STORM:
			return day_night != null
		EventKind.ABUNDANCE:
			return foliage_spawner != null
	return false


# ================= 各事件的开始 / 结束处理（返回横幅文案） =================

## 兽群迁徙：同一物种 4-6 只从地图边缘聚簇涌入（结束不回收，并入生态自然调控）
func _start_herd() -> String:
	var sid: String = HERD_POOL[randi() % HERD_POOL.size()]
	var count: int = randi_range(HERD_SIZE_MIN, HERD_SIZE_MAX)
	director.spawn_herd(sid, count)
	var species_name: String = sid
	var def: DinoSpecies.SpeciesDef = DinoSpecies.by_id(sid)
	if def != null:
		species_name = def.name
	return "一群%s正在迁徙，涌入这片土地！" % species_name


func _end_herd() -> String:
	return "迁徙的兽群已融入这片土地。"


## 风暴：生效期雾密度 ×3、太阳能量 ×0.6，结束恢复原状
func _start_storm() -> String:
	day_night.set_storm(true)
	return "风暴来袭！浓雾蔽日，阳光黯淡……"


func _end_storm() -> String:
	day_night.set_storm(false)
	return "风暴平息，天空放晴。"


## 丰饶期：重生间隔 ÷4 并立即补生 5 株植物，结束恢复
func _start_abundance() -> String:
	foliage_spawner.set_abundant(true)
	return "丰饶期降临！植物疯长，食物遍地。"


func _end_abundance() -> String:
	foliage_spawner.set_abundant(false)
	return "丰饶期结束，植被恢复常态。"


## 从树移除（死亡重开释放旧实例）时回滚未结束的世界效果，避免风暴/丰饶期跨局残留
func _exit_tree() -> void:
	if _state != State.ACTIVE:
		return
	match _active_kind:
		EventKind.STORM:
			if day_night != null:
				day_night.set_storm(false)
		EventKind.ABUNDANCE:
			if foliage_spawner != null:
				foliage_spawner.set_abundant(false)
