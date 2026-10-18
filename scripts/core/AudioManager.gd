extends Node
## 音频总线：启动时幂等创建 SFX / Ambient 总线（send 到 Master），并按设置应用音量
## 依赖 autoload 注册顺序：GameState 必须在 AudioManager 之前注册。

const BUS_SFX := "SFX"
const BUS_AMBIENT := "Ambient"
const BUS_MASTER := "Master"

## 静音阈值：线性音量低于等于该值时直接压到 -80dB（避免 linear_to_db(0) 产生 -inf）
const MUTE_LINEAR_THRESHOLD := 0.0001
const MUTE_DB := -80.0


func _ready() -> void:
	_ensure_buses()
	# GameState 在前注册，启动时即可安全引用其设置
	apply_settings(GameState.settings)


## 幂等创建总线：遍历现有总线查名，已存在则跳过，缺才新增并发送到 Master
func _ensure_buses() -> void:
	_ensure_bus(BUS_SFX)
	_ensure_bus(BUS_AMBIENT)


## 确保单个总线存在：按名查找，缺才 add_bus + set_bus_name + set_bus_send
func _ensure_bus(bus_name: String) -> void:
	for i in AudioServer.bus_count:
		if AudioServer.get_bus_name(i) == bus_name:
			return
	var idx := AudioServer.bus_count
	AudioServer.add_bus(idx)
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, BUS_MASTER)


## 设置总线音量：linear 0..1 → dB（linear<=0.0001 静音 -80dB）；总线不存在时忽略
func set_bus_volume_linear(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	var db := MUTE_DB if linear <= MUTE_LINEAR_THRESHOLD else linear_to_db(linear)
	AudioServer.set_bus_volume_db(idx, db)


## 从设置字典读三路音量并应用到对应总线（缺键时该路保持不动）
func apply_settings(s: Dictionary) -> void:
	if s.has("master_volume"):
		set_bus_volume_linear(BUS_MASTER, float(s["master_volume"]))
	if s.has("sfx_volume"):
		set_bus_volume_linear(BUS_SFX, float(s["sfx_volume"]))
	if s.has("ambient_volume"):
		set_bus_volume_linear(BUS_AMBIENT, float(s["ambient_volume"]))
