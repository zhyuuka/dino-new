class_name DayNightCycle
extends Node
## 昼夜循环子系统：持有太阳光 / 世界环境 / 地图基调引用，推进 day_t 并驱动
## 光照能量、太阳颜色、天空渐变与雾色的昼夜变化。
## 由 Main 编排器每帧调用 update(delta)；day_t 全局连续（死亡重开不清零）。

const DAY_LENGTH: float = 120.0

var sun_light: DirectionalLight3D
var world_env: WorldEnvironment
var _map_def: Maps.MapDef = null

## 一天进度 0..1（0.3 = 清晨起步）
var day_t: float = 0.3

## 风暴状态（随机事件系统控制）：生效期雾密度 ×3、太阳能量 ×0.6
var _storm_on: bool = false
var _storm_fog_base: float = 0.006  # 风暴开始时记录的雾密度基准（取自 _map_def.fog_density）


## 注入场景中的太阳光与世界环境节点（Main._ready 时调用）
func setup(sun: DirectionalLight3D, env: WorldEnvironment) -> void:
	sun_light = sun
	world_env = env


## 选图 / 读档后注入地图的天空与雾基调（未注入时使用默认基调）
func set_map_def(def: Maps.MapDef) -> void:
	_map_def = def


## 风暴开关（随机事件系统调用）：开启时记录雾密度基准，关闭时恢复原密度。
## 太阳能量的 ×0.6 与雾密度 ×3 统一在 _apply_day_night 末尾叠加，
## 逐帧重算后再乘系数，不会被昼夜公式的每帧写入覆盖。
func set_storm(on: bool) -> void:
	if on and not _storm_on:
		_storm_fog_base = _map_def.fog_density if _map_def != null else 0.006
	var was_on: bool = _storm_on
	_storm_on = on
	# 仅在"开 → 关"的转换沿恢复基准密度：从未开过风暴时误调 set_storm(false) 不再误写雾密度
	if was_on and not _storm_on and world_env != null and world_env.environment != null:
		world_env.environment.fog_density = _storm_fog_base  # 结束恢复基准密度


## 每帧推进一天进度并应用光照变化
func update(delta: float) -> void:
	day_t = fmod(day_t + delta / DAY_LENGTH, 1.0)
	_apply_day_night()


func _apply_day_night() -> void:
	var h: float = sin(day_t * TAU)                 # -1 午夜 .. 1 正午
	var day: float = clampf(h, 0.0, 1.0)            # 0 夜 .. 1 昼
	var twilight: float = clampf(1.0 - abs(h) * 3.0, 0.0, 1.0)  # 近地平线辉光
	# 地图基调（日间基色），未选地图时回退默认
	var day_top := Color(0.35, 0.6, 0.85)
	var day_horizon := Color(0.7, 0.82, 0.9)
	var sun_day := Color(1.0, 0.98, 0.9)
	var fog_base := Color(0.8, 0.85, 0.8)
	if _map_def != null:
		day_top = _map_def.sky_top
		day_horizon = _map_def.sky_horizon
		sun_day = _map_def.sun_color
		fog_base = _map_def.fog_color
	if sun_light != null:
		sun_light.light_energy = lerpf(0.15, 1.25, day)
		var day_col := sun_day
		var dusk_col := Color(1.0, 0.55, 0.3)
		var night_col := Color(0.4, 0.5, 0.8)
		var col := night_col.lerp(day_col, day)
		col = col.lerp(dusk_col, twilight * 0.6)
		sun_light.light_color = col
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment
		var top := Color(0.1, 0.15, 0.35).lerp(day_top, day)
		var hor := Color(0.2, 0.25, 0.4).lerp(day_horizon, day)
		hor = hor.lerp(Color(1.0, 0.5, 0.3), twilight * 0.5)
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sm := env.sky.sky_material as ProceduralSkyMaterial
			sm.sky_top_color = top
			sm.sky_horizon_color = hor
		env.ambient_light_energy = lerpf(0.25, 0.7, day)
		# 雾色随昼夜微调（夜间偏暗）
		if env.fog_enabled:
			env.fog_light_color = fog_base.lerp(Color(0.18, 0.22, 0.32), (1.0 - day) * 0.5)
	# 风暴系数（纯乘法叠加，不改变既有昼夜公式数值）：雾密度 ×3、太阳能量 ×0.6
	if _storm_on:
		if world_env != null and world_env.environment != null:
			world_env.environment.fog_density = _storm_fog_base * 3.0
		if sun_light != null:
			sun_light.light_energy *= 0.6
